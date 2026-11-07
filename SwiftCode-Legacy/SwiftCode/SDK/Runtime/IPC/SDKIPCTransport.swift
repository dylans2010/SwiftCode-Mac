import Foundation

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
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }
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

private enum SDKIPCFraming {
    static let newline: UInt8 = 0x0A
    static let readChunkSize = 65_536
    static let writeChunkSize = 65_536
}

public actor SDKIPCTransport {

    private let readHandle: FileHandle
    private let writeHandle: FileHandle
    private var pending = Data()
    private var isClosed = false
    private var isDesynchronized = false

    public init(stdin: Pipe, stdout: Pipe) {
        self.readHandle = stdout.fileHandleForReading
        self.writeHandle = stdin.fileHandleForWriting
    }

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

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        try? readHandle.close()
        try? writeHandle.close()
    }

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
