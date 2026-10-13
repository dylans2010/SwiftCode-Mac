import Foundation

// MARK: - SDKJSONValue
//
// A JSON value type owned by the IPC transport layer. The dispatcher uses it
// for payloads whose schema is not known at compile time (e.g. loosely-typed
// event data), so unknown or evolving extension payloads can cross the
// boundary without a dedicated Codable model per method.

public indirect enum SDKJSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([SDKJSONValue])
    case object([String: SDKJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        // Bool before numbers: JSONDecoder rejects numbers for Bool, so this
        // only matches true/false literals.
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }
        // Int before Double: real JSON numbers like 3 decode as .int(3),
        // while 3.5 (or integers beyond Int's range) fall through to .double.
        if let int = try? container.decode(Int.self) {
            self = .int(int)
            return
        }
        if let double = try? container.decode(Double.self) {
            self = .double(double)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let array = try? container.decode([SDKJSONValue].self) {
            self = .array(array)
            return
        }
        if let object = try? container.decode([String: SDKJSONValue].self) {
            self = .object(object)
            return
        }
        throw DecodingError.typeMismatch(
            SDKJSONValue.self,
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Expected a JSON value (string, number, boolean, null, array, or object)."
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Framing constants

/// Wire-level constants shared by the transport's read/write paths.
private enum SDKIPCFraming {
    /// NDJSON record separator.
    static let newline: UInt8 = 0x0A
    /// Bytes requested per read syscall. Large enough to move 1 MiB frames
    /// in few syscalls; small enough to keep per-read latency bounded.
    static let readChunkSize = 65_536
    /// Bytes per write syscall. Keeps any single write bounded even though
    /// Foundation's write is all-or-throw (see sendMessage).
    static let writeChunkSize = 65_536
}

// MARK: - SDKIPCTransport
//
// stdio NDJSON transport for the SDK runtime (spec §10.4).
//
// Framing (both directions):
//   - One envelope per line, terminated by `\n` (0x0A).
//   - UTF-8 encoded JSON; `SDKIPCCodec` guarantees encoded frames contain no
//     literal newline bytes, so a line boundary is always a frame boundary.
//   - Maximum 1 MiB per frame (`SDKIPCCodec.maxMessageBytes`), enforced
//     *during* accumulation — an oversized frame throws
//     `.resourceLimitExceeded` the moment the bound is exceeded instead of
//     buffering unbounded input.
//
// Pipe directions (host's point of view):
//   - `stdin`  (the extension process's stdin pipe): host → extension.
//     Frames are written to `stdin.fileHandleForWriting`.
//   - `stdout` (the extension process's stdout pipe): extension → host.
//     Frames are read from `stdout.fileHandleForReading`.
//
// Concurrency: this is a plain actor, never `@MainActor`. All blocking I/O
// runs on the actor's executor, never the main thread. `readMessage` is the
// only reader; concurrent `readMessage` calls serialize on the actor, which
// is what keeps frame boundaries intact. `sendMessage` calls serialize the
// same way, so frames never interleave on the wire.

public actor SDKIPCTransport {

    /// Extension → host: the extension process's stdout pipe, read end.
    private let readHandle: FileHandle
    /// Host → extension: the extension process's stdin pipe, write end.
    private let writeHandle: FileHandle
    /// Bytes already read from the pipe that belong to the *next* frame
    /// (a single read syscall can deliver more than one line).
    private var pending = Data()
    /// Set after `close()`; further I/O throws `.runtimeUnavailable`.
    private var isClosed = false
    /// Set when a frame exceeds the size bound mid-accumulation. The partial
    /// frame is discarded and the stream position is unknown, so further
    /// reads throw `.ipcMalformed` until the transport is replaced.
    private var isDesynchronized = false

    /// - Parameters:
    ///   - stdin: The extension process's stdin pipe (host → extension).
    ///   - stdout: The extension process's stdout pipe (extension → host).
    public init(stdin: Pipe, stdout: Pipe) {
        self.readHandle = stdout.fileHandleForReading
        self.writeHandle = stdin.fileHandleForWriting
    }

    // MARK: - Reading

    /// Reads exactly one newline-terminated frame (without the newline) from
    /// the extension's stdout.
    ///
    /// Bytes accumulate across read syscalls: a frame split over several
    /// pipe reads is reassembled, and bytes after the newline are kept in
    /// `pending` for the next call. The size bound is enforced on every
    /// append — never after the whole frame is buffered.
    ///
    /// - Throws:
    ///   - `.resourceLimitExceeded` the moment the accumulated frame exceeds
    ///     `SDKIPCCodec.maxMessageBytes`.
    ///   - `.ipcMalformed` when EOF arrives with a partial (unterminated)
    ///     frame, when a read fails without a connection-level cause, or
    ///     when the stream was desynchronized by a prior oversized frame.
    ///   - `.runtimeCrash` ("Extension runtime closed the connection.") on
    ///     clean EOF with no pending data, or when the pipe breaks
    ///     mid-read.
    ///   - `.runtimeUnavailable` when called after `close()`.
    public func readMessage() async throws -> Data {
        if isClosed {
            throw SDKError(
                code: .runtimeUnavailable,
                message: "IPC transport is closed.",
                suggestion: "The extension session has ended; start a new session to communicate."
            )
        }
        if isDesynchronized {
            throw SDKError(
                code: .ipcMalformed,
                message: "IPC stream desynchronized after an oversized frame; the connection must be reset.",
                suggestion: "Terminate and relaunch the extension runtime."
            )
        }

        let limit = SDKIPCCodec.maxMessageBytes

        // Fast path: a previous read already buffered a complete line.
        if let newlineIndex = pending.firstIndex(of: SDKIPCFraming.newline) {
            let frame = Data(pending[..<newlineIndex])
            pending.removeSubrange(pending.startIndex...newlineIndex)
            return frame
        }

        var frame = pending
        pending.removeAll(keepingCapacity: true)

        while true {
            let chunk: Data?
            do {
                chunk = try readHandle.read(upToCount: SDKIPCFraming.readChunkSize)
            } catch {
                throw SDKError(
                    code: .runtimeCrash,
                    message: "Lost connection to the extension runtime while reading a message.",
                    suggestion: "Check the extension's stderr log; the runtime may have crashed.",
                    diagnostics: [
                        "underlyingError": (error as NSError).localizedDescription,
                        "partialBytes": "\(frame.count)"
                    ]
                )
            }
            // nil or empty: EOF on the pipe.
            guard let chunk, !chunk.isEmpty else {
                if frame.isEmpty {
                    throw SDKError(
                        code: .runtimeCrash,
                        message: "Extension runtime closed the connection.",
                        suggestion: "Check the extension's stderr log; the runtime exited without sending a message."
                    )
                }
                throw SDKError(
                    code: .ipcMalformed,
                    message: "Extension runtime closed the connection in the middle of a message.",
                    suggestion: "Check the extension's stderr log for a crash.",
                    diagnostics: ["partialBytes": "\(frame.count)"]
                )
            }

            if let newlineIndex = chunk.firstIndex(of: SDKIPCFraming.newline) {
                let head = chunk[..<newlineIndex]
                if frame.count + head.count > limit {
                    discardAfterOversize()
                    throw Self.oversizeError(limit: limit)
                }
                frame.append(contentsOf: head)
                // Everything after the newline belongs to the next frame.
                pending = Data(chunk[chunk.index(after: newlineIndex)...])
                return frame
            }

            if frame.count + chunk.count > limit {
                discardAfterOversize()
                throw Self.oversizeError(limit: limit)
            }
            frame.append(contentsOf: chunk)
        }
    }

    // MARK: - Writing

    /// Writes one frame to the extension's stdin, followed by `\n`.
    ///
    /// The payload must already be a single newline-free line
    /// (`SDKIPCCodec` guarantees this for encoded envelopes); the check here
    /// is defense in depth so a framing violation can never corrupt the
    /// stream for subsequent frames.
    ///
    /// Foundation's `FileHandle.write(contentsOf:)` is all-or-throw, so a
    /// partial write surfaces as an error rather than silent truncation. The
    /// frame is still issued in bounded chunks so no single syscall is
    /// arbitrarily large. Any write failure means the pipe is broken, which
    /// is reported as `.runtimeCrash`.
    ///
    /// - Throws:
    ///   - `.invalidArgument` when `data` contains a `\n` byte.
    ///   - `.resourceLimitExceeded` when `data` exceeds
    ///     `SDKIPCCodec.maxMessageBytes`.
    ///   - `.runtimeCrash` when the write fails (broken pipe — the runtime
    ///     is gone or its stdin was closed).
    ///   - `.runtimeUnavailable` when called after `close()`.
    public func sendMessage(_ data: Data) async throws {
        if isClosed {
            throw SDKError(
                code: .runtimeUnavailable,
                message: "IPC transport is closed.",
                suggestion: "The extension session has ended; start a new session to communicate."
            )
        }
        if data.contains(SDKIPCFraming.newline) {
            throw SDKError(
                code: .invalidArgument,
                message: "Outbound IPC frame contains a newline; frames must be single-line.",
                suggestion: "Encode the envelope with SDKIPCCodec, which guarantees newline-free output."
            )
        }
        let limit = SDKIPCCodec.maxMessageBytes
        if data.count > limit {
            throw Self.oversizeError(limit: limit)
        }

        var frame = Data()
        frame.reserveCapacity(data.count + 1)
        frame.append(data)
        frame.append(SDKIPCFraming.newline)

        var offset = frame.startIndex
        while offset < frame.endIndex {
            let remaining = frame.distance(from: offset, to: frame.endIndex)
            let end = frame.index(offset, offsetBy: min(SDKIPCFraming.writeChunkSize, remaining))
            do {
                try writeHandle.write(contentsOf: Data(frame[offset..<end]))
            } catch {
                throw SDKError(
                    code: .runtimeCrash,
                    message: "Failed to write to the extension runtime; the connection may be closed.",
                    suggestion: "Check whether the extension runtime is still running.",
                    diagnostics: [
                        "underlyingError": (error as NSError).localizedDescription,
                        "bytesWritten": "\(frame.distance(from: frame.startIndex, to: offset))",
                        "frameBytes": "\(frame.count)"
                    ]
                )
            }
            offset = end
        }
    }

    // MARK: - Shutdown

    /// Closes both pipe ends. Idempotent. An in-flight `readMessage` blocked
    /// in a read syscall surfaces the close as a read error (mapped to
    /// `.runtimeCrash`); callers should treat errors arriving after `close()`
    /// as expected shutdown, not as a crash to report.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        try? readHandle.close()
        try? writeHandle.close()
    }

    // MARK: - Private

    /// Drops all buffered state after an oversized frame and marks the
    /// stream desynchronized: the frame's true end is unknown, so the next
    /// newline on the wire cannot be trusted as a frame boundary.
    private func discardAfterOversize() {
        isDesynchronized = true
        pending.removeAll()
    }

    private static func oversizeError(limit: Int) -> SDKError {
        SDKError(
            code: .resourceLimitExceeded,
            message: "IPC message exceeds the \(limit)-byte limit.",
            suggestion: "Reduce the payload size (e.g. request a bounded diff) and retry."
        )
    }
}
