import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Muse Code MSP bridge (Wave 16, Slice B)
//
// Ported from Legacy (Dylan's own code; direct port authorised
// under MIT):
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MuseCodeMSPBridge.swift`
//     — the JSON-RPC host session over the `muse` CLI.
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MuseCodeCLIHelper.swift`
//     — only the `MuseCodeCLIError` cases the bridge throws; the
//     helper itself is NOT ported (see below).
//
// What this is: the transport for "Assist with Meta". One `muse
// serve` child process, NDJSON (one JSON-RPC 2.0 message per line)
// over its stdin/stdout, with string request ids. The wire methods
// Legacy used, verified live from Legacy @ d51a8f0d:
//   `initialize` (clientInfo `{name: "swiftcode", title:
//   "SwiftCode", version: "1.0.0"}`) + `initialized` notification,
//   `model/list`, `session/start`, `session/resume`,
//   `session/setModel`, `turn/start`, `turn/unqueue`,
//   `turn/cancel`, `approval/decide`. Incoming server requests
//   (`approval/request`, …) are answered here; incoming
//   notifications (`item/started`, `item/delta`, `item/completed`,
//   `turn/completed`, `turn/unqueued`, `session/modelChanged`,
//   `approval/requested`, `approval/resolved`) are delivered to the
//   notification handler — the turn executor owns their meaning.
//
// Public corroboration (not the source of the protocol — Legacy
// is): Meta's own Muse Code docs say `muse serve` "hosts a session
// over stdio using Meta's session protocol" and `muse schema`
// exports that wire schema; the TypeScript/Python SDKs wrap it.
//
// What is deliberately different from Legacy:
//   * No `@MainActor` singleton, no Combine, no `os.Logger`, no
//     `SecRandomCopyBytes` (Darwin-only): this is an actor, so the
//     provider, the lifecycle manager and tests can each hold it,
//     and it stays Linux-buildable. UUIDv7 uses Swift's own random
//     bytes. There is no logging here; errors carry the message.
//   * The wire values are Ycode's `AnyJSON` / `JSONRPCMessage`
//     (the host's existing JSON-RPC types) instead of
//     `MuseCodeAnyCodable` / `[String: Any]` dictionaries. One
//     consequence: `sendCommand` returns the whole response
//     message (Legacy returned the whole `[String: Any]` response
//     dict too), and callers read `["result"]` from it.
//   * Request ids are UUID strings (Legacy's `sendCommand` used
//     `UUID().uuidString`); session/turn `commandId`s are UUIDv7
//     (Legacy's `MuseUUIDv7.generate()`), ported verbatim in shape.
//   * `MuseCodeCLIHelper` is NOT ported here: the provider already
//     locates the binary (`MetaAssistProvider.executableURL`) and
//     checks credential files by existence only. The helper's
//     credential-*reading* (`readAuthInfo`, which decoded
//     access tokens / API keys out of `auth.json`), its login flow
//     (`runLoginFlow`, interactive browser sign-in), its
//     `ensureMuseConfigHealth` (which rewrote
//     `~/.config/muse/settings.json`) and `installCLIViaNPM` are
//     not ported anywhere in this slice: Ycode never reads a
//     credential file, never runs an interactive login, and never
//     rewrites the user's Muse config.
//   * `JSONRPCPeer` is NOT reused: it mints integer request ids
//     and answers server requests through async `Work` closures,
//     while MSP needs string ids and a synchronous "I am handling
//     this" acknowledgement for `approval/request`. The bridge
//     reuses only `JSONRPCMessage.parse` and `LineFramer`.

/// An error the MSP host returns (Legacy `MspError`).
public struct MuseCodeMSPError: Error, LocalizedError, Sendable, Equatable {
    public let code: Int
    public let message: String
    public let kind: String?
    /// The error's `data` object, when the host sent one.
    public let data: AnyJSON?

    public init(code: Int, message: String, kind: String? = nil, data: AnyJSON? = nil) {
        self.code = code
        self.message = message
        self.kind = kind
        self.data = data
    }

    /// Legacy's `MspError.reason`: `data["reason"]`.
    public var reason: String? { data?["reason"]?.string }

    public var errorDescription: String? { message }
}

/// The CLI-side failures (Legacy `MuseCodeCLIError`, same cases
/// and wording — the bridge is the only place that throws them).
public enum MuseCodeCLIError: Error, LocalizedError, Sendable, Equatable {
    case executableNotFound
    case installationFailed(String)
    case executionFailed(exitCode: Int32, stderr: String)
    case timeout
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "The 'muse' CLI executable was not found on your system."
        case .installationFailed(let msg):
            return "Failed to install 'muse' CLI: \(msg)"
        case .executionFailed(let code, let stderr):
            return "CLI execution failed with code \(code): \(stderr)"
        case .timeout:
            return "CLI command timed out."
        case .cancelled:
            return "CLI operation was cancelled."
        }
    }
}

/// UUIDv7 (Legacy `MuseUUIDv7`): the millisecond timestamp in the
/// first 48 bits, version 7 in the next nibble, RFC 9562 variant
/// in the next two bits, the rest random. Portable: Swift's own
/// random bytes, never `SecRandomCopyBytes`.
public enum MuseUUIDv7 {
    public static func generate() -> String {
        var bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)
        bytes[0] = UInt8((ms >> 40) & 0xFF)
        bytes[1] = UInt8((ms >> 32) & 0xFF)
        bytes[2] = UInt8((ms >> 24) & 0xFF)
        bytes[3] = UInt8((ms >> 16) & 0xFF)
        bytes[4] = UInt8((ms >> 8) & 0xFF)
        bytes[5] = UInt8(ms & 0xFF)
        // Version 7: (0x70 | (random & 0x0F))
        bytes[6] = 0x70 | (bytes[6] & 0x0F)
        // Variant 1 (RFC 9562): (0x80 | (random & 0x3F))
        bytes[8] = 0x80 | (bytes[8] & 0x3F)
        return String(
            format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
    }

    /// The embedded millisecond timestamp, when the id is a UUIDv7.
    public static func timestampMilliseconds(of id: String) -> UInt64? {
        let hex = id.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32, let ms = UInt64(hex.prefix(12), radix: 16) else { return nil }
        return ms
    }
}

/// One `muse serve` host session: the NDJSON JSON-RPC transport
/// the Meta turn executor drives.
///
/// One process per bridge. The bridge is an actor with a shared
/// instance (Legacy's `MuseCodeMSPBridge.shared`): the provider,
/// the lifecycle manager and the turn executor all drive the same
/// host, so a second `startHost` while one runs is a no-op and
/// `stopHost` ends the session for everyone. Tests construct
/// their own bridge to drive a fixture `muse` script.
public actor MuseCodeMSPBridge {
    public static let shared = MuseCodeMSPBridge()

    /// The argv for the host (Legacy `startHost`): `serve`, or
    /// `--base-url <url> serve` when the other-models proxy serves
    /// the models (see `MuseOtherModelsBridge`).
    public static func hostArguments(baseURL: String?) -> [String] {
        if let base = baseURL, !base.isEmpty {
            return ["--base-url", base, "serve"]
        }
        return ["serve"]
    }

    /// The host's environment (Legacy `startHost`): the inherited
    /// environment with the Homebrew / local bin dirs appended to
    /// PATH, so a GUI-launched IDE still finds a user-installed
    /// `muse` next to its helpers.
    public static func hostEnvironment(parent: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = parent
        if let path = env["PATH"] {
            env["PATH"] = path + ":/opt/homebrew/bin:/usr/local/bin"
        }
        return env
    }

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    public private(set) var isRunning: Bool = false
    public private(set) var isInitialized: Bool = false
    private var pending: [String: CheckedContinuation<AnyJSON, Error>] = [:]
    private var framer = LineFramer()
    private var notificationHandler: (@Sendable (String, AnyJSON?) -> Void)?
    private var serverRequestHandler: (@Sendable (JSONRPCID, String, AnyJSON?) -> AnyJSON?)?

    public init() {}

    public func markInitialized() { isInitialized = true }

    /// Starts the host, unless one is already running (Legacy
    /// `startHost` early-returns then too).
    public func startHost(executable: URL, workspaceRoot: String, baseURL: String? = nil) async throws {
        guard !isRunning else { return }

        // A write to a host that has exited fails (EPIPE) instead
        // of ending Ycode (same as `ACPClient`).
        signal(SIGPIPE, SIG_IGN)

        let proc = Process()
        proc.executableURL = executable
        proc.arguments = Self.hostArguments(baseURL: baseURL)
        proc.currentDirectoryURL = URL(fileURLWithPath: workspaceRoot)
        proc.environment = Self.hostEnvironment()

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe

        stdinPipe = inPipe
        stdoutPipe = outPipe
        process = proc

        proc.terminationHandler = { [weak self] _ in
            guard let self else { return }
            Task { await self.handleTermination() }
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            Task { await self.handleIncomingData(data) }
        }

        do {
            try proc.run()
        } catch {
            process = nil
            stdinPipe = nil
            stdoutPipe = nil
            throw error
        }
        isRunning = true
    }

    /// The handler for server notifications (`item/delta`,
    /// `turn/completed`, …). Replaces any previous handler.
    public func setNotificationHandler(_ handler: (@Sendable (String, AnyJSON?) -> Void)?) {
        notificationHandler = handler
    }

    /// The handler for server requests (`approval/request`, …):
    /// its result is sent back, or a `-32601 Method not found`
    /// error when it returns nil — except `approval/request`,
    /// which Legacy's cookbook acknowledgement answers with `{}`
    /// ("I am handling this") when no handler is installed.
    public func setServerRequestHandler(_ handler: (@Sendable (JSONRPCID, String, AnyJSON?) -> AnyJSON?)?) {
        serverRequestHandler = handler
    }

    /// Sends a notification (no id, no reply expected).
    public func sendNotification(method: String, params: AnyJSON? = nil) throws {
        guard isRunning, let inPipe = stdinPipe else {
            throw MuseCodeCLIError.executionFailed(exitCode: -1, stderr: "MSP host process not running")
        }
        try writeLine(.notification(method: method, params: params), to: inPipe)
    }

    /// Sends a request and waits for its response. Returns the
    /// whole response message (Legacy returned the whole response
    /// dict); callers read `["result"]` from it. A response error
    /// throws `MuseCodeMSPError` with the host's code, message,
    /// kind and data.
    public func sendCommand(method: String, params: AnyJSON? = nil) async throws -> AnyJSON {
        guard isRunning, let inPipe = stdinPipe else {
            throw MuseCodeCLIError.executionFailed(exitCode: -1, stderr: "MSP host process not running")
        }
        let id = JSONRPCID.string(UUID().uuidString)
        let message = JSONRPCMessage.request(id: id, method: method, params: params)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AnyJSON, Error>) in
            pending[id.description] = continuation
            do {
                try writeLine(message, to: inPipe)
            } catch {
                pending.removeValue(forKey: id.description)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Answers a server request with a result.
    public func sendResponse(id: JSONRPCID, result: AnyJSON) throws {
        guard isRunning, let inPipe = stdinPipe else { return }
        try writeLine(.result(id: id, result: result), to: inPipe)
    }

    /// Answers a server request with an error.
    public func sendRPCError(id: JSONRPCID, code: Int, message: String) throws {
        guard isRunning, let inPipe = stdinPipe else { return }
        try writeLine(.error(id: id, error: JSONRPCError(code: code, message: message)), to: inPipe)
    }

    /// Stops the host: terminates the process, fails every pending
    /// request with `.cancelled`, and clears all state (Legacy
    /// `stopHost`).
    public func stopHost() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        isRunning = false
        isInitialized = false
        framer = LineFramer()
        failPending(MuseCodeCLIError.cancelled)
    }

    // MARK: - Incoming bytes

    private func writeLine(_ message: JSONRPCMessage, to pipe: Pipe) throws {
        pipe.fileHandleForWriting.write(message.line)
    }

    private func handleIncomingData(_ data: Data) {
        for line in framer.append(data) {
            handleIncomingLine(line)
        }
    }

    private func handleIncomingLine(_ line: Data) {
        let message: JSONRPCMessage
        do {
            message = try JSONRPCMessage.parse(line)
        } catch {
            return // A malformed line never aborts the session.
        }
        switch message {
        case .request(let id, let method, let params):
            if let handler = serverRequestHandler, let result = handler(id, method, params) {
                try? sendResponse(id: id, result: result)
            } else if method == "approval/request" {
                // Muse SDK Cookbook: immediately acknowledge with {}
                // ("I am handling this"). The real decision arrives
                // as an `approval/requested` notification and is
                // answered with `approval/decide` by the executor.
                try? sendResponse(id: id, result: .object([:]))
            } else {
                try? sendRPCError(id: id, code: -32601, message: "Method not found: \(method)")
            }
        case .result(let id, let result):
            if let cont = pending.removeValue(forKey: id.description) {
                // The whole response message, as Legacy returned the
                // whole response dict: callers read ["result"] off it.
                cont.resume(returning: ["jsonrpc": "2.0", "id": id.json, "result": result])
            }
        case .error(let id, let error):
            guard let id else { return }
            if let cont = pending.removeValue(forKey: id.description) {
                // Legacy read the kind from `error.data["kind"]`
                // (or `error["kind"]`); JSONRPCError carries it in
                // `data`, so it is recovered here.
                cont.resume(throwing: MuseCodeMSPError(code: error.code, message: error.message,
                                                       kind: error.data?["kind"]?.string, data: error.data))
            }
        case .notification(let method, let params):
            notificationHandler?(method, params)
        }
    }

    private func handleTermination() {
        isRunning = false
        isInitialized = false
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        framer = LineFramer()
        failPending(MuseCodeCLIError.executionFailed(exitCode: -1, stderr: "MSP host process terminated."))
    }

    private func failPending(_ error: Error) {
        let waiting = pending
        pending.removeAll()
        for (_, cont) in waiting {
            cont.resume(throwing: error)
        }
    }
}
