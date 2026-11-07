import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public struct MuseCodeMSPError: Error, LocalizedError, Sendable, Equatable {
    public let code: Int
    public let message: String
    public let kind: String?
    public let data: AnyJSON?

    public init(code: Int, message: String, kind: String? = nil, data: AnyJSON? = nil) {
        self.code = code
        self.message = message
        self.kind = kind
        self.data = data
    }

    public var reason: String? { data?["reason"]?.string }

    public var errorDescription: String? { message }
}

public enum MuseCodeCLIError: Error, LocalizedError, Sendable, Equatable {
    case executableNotFound
    case installationFailed(String)
    case executionFailed(exitCode: Int32, stderr: String)
    case timeout
    case cancelled
    case turnTimeout(TimeInterval)

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
        case .turnTimeout(let seconds):
            return "The Meta turn timed out after \(Int(seconds)) seconds. The Muse host was stopped, so the turn produced no result."
        case .cancelled:
            return "CLI operation was cancelled."
        }
    }
}

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
        bytes[6] = 0x70 | (bytes[6] & 0x0F)
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

    public static func timestampMilliseconds(of id: String) -> UInt64? {
        let hex = id.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32, let ms = UInt64(hex.prefix(12), radix: 16) else { return nil }
        return ms
    }
}

public actor MuseCodeMSPBridge {
    public static let shared = MuseCodeMSPBridge()

    public static func hostArguments(baseURL: String?) -> [String] {
        if let base = baseURL, !base.isEmpty {
            return ["--base-url", base, "serve"]
        }
        return ["serve"]
    }

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

    public func startHost(executable: URL, workspaceRoot: String, baseURL: String? = nil) async throws {
        guard !isRunning else { return }

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

    public func setNotificationHandler(_ handler: (@Sendable (String, AnyJSON?) -> Void)?) {
        notificationHandler = handler
    }

    public func setServerRequestHandler(_ handler: (@Sendable (JSONRPCID, String, AnyJSON?) -> AnyJSON?)?) {
        serverRequestHandler = handler
    }

    public func sendNotification(method: String, params: AnyJSON? = nil) throws {
        guard isRunning, let inPipe = stdinPipe else {
            throw MuseCodeCLIError.executionFailed(exitCode: -1, stderr: "MSP host process not running")
        }
        try writeLine(.notification(method: method, params: params), to: inPipe)
    }

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

    public func sendResponse(id: JSONRPCID, result: AnyJSON) throws {
        guard isRunning, let inPipe = stdinPipe else { return }
        try writeLine(.result(id: id, result: result), to: inPipe)
    }

    public func sendRPCError(id: JSONRPCID, code: Int, message: String) throws {
        guard isRunning, let inPipe = stdinPipe else { return }
        try writeLine(.error(id: id, error: JSONRPCError(code: code, message: message)), to: inPipe)
    }

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
            return
        }
        switch message {
        case .request(let id, let method, let params):
            if let handler = serverRequestHandler, let result = handler(id, method, params) {
                try? sendResponse(id: id, result: result)
            } else if method == "approval/request" {
                try? sendResponse(id: id, result: .object([:]))
            } else {
                try? sendRPCError(id: id, code: -32601, message: "Method not found: \(method)")
            }
        case .result(let id, let result):
            if let cont = pending.removeValue(forKey: id.description) {
                cont.resume(returning: ["jsonrpc": "2.0", "id": id.json, "result": result])
            }
        case .error(let id, let error):
            guard let id else { return }
            if let cont = pending.removeValue(forKey: id.description) {
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

public struct MspError: Error, LocalizedError, @unchecked Sendable {
    public let code: Int
    public let message: String
    public let kind: String?
    public let data: [String: Any]?

    public init(code: Int, message: String, kind: String? = nil, data: [String: Any]? = nil) {
        self.code = code
        self.message = message
        self.kind = kind
        self.data = data
    }

    public var reason: String? {
        data?["reason"] as? String
    }

    public var errorDescription: String? { message }
}

public struct MuseCodeMSPMessage: Codable, Sendable {
    public let jsonrpc: String
    public let id: String?
    public let method: String?
    public let params: MuseCodeAnyCodable?
    public let result: MuseCodeAnyCodable?
    public let error: MuseCodeAnyCodable?

    public init(jsonrpc: String = "2.0", id: String? = nil, method: String? = nil, params: MuseCodeAnyCodable? = nil, result: MuseCodeAnyCodable? = nil, error: MuseCodeAnyCodable? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }
}

public struct MuseCodeAnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([MuseCodeAnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: MuseCodeAnyCodable].self) {
            var dict = [String: Any]()
            for (k, v) in dictionary {
                dict[k] = v.value
            }
            value = dict
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = try encoder.singleValueContainer()
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            let encodableArray = array.map { MuseCodeAnyCodable($0) }
            try container.encode(encodableArray)
        } else if let dictionary = value as? [String: Any] {
            var encodableDict = [String: MuseCodeAnyCodable]()
            for (k, v) in dictionary {
                encodableDict[k] = MuseCodeAnyCodable(v)
            }
            try container.encode(encodableDict)
        } else {
            try container.encodeNil()
        }
    }
}
