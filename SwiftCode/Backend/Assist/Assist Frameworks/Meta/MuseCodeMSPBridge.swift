//
//  MuseCodeMSPBridge.swift
//  SwiftCode
//
//  IPC Bridge and session transport for Muse Code MSP protocol ("Assist with Meta").
//

import Foundation

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

public enum MuseUUIDv7 {
    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)

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
}

@MainActor
public final class MuseCodeMSPBridge: @unchecked Sendable {
    public static let shared = MuseCodeMSPBridge()

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    public private(set) var isRunning: Bool = false
    private var pendingContinuations: [String: CheckedContinuation<String, Error>] = [:]
    private var notificationHandler: ((String, [String: Any]) -> Void)?
    private var incomingBuffer = Data()

    private init() {}

    public func startHost(workspaceRoot: String) async throws {
        guard !isRunning else { return }

        guard let executablePath = MuseCodeCLIHelper.shared.discoverExecutablePath() else {
            throw MuseCodeCLIError.executableNotFound
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = ["serve"]
        proc.currentDirectoryURL = URL(fileURLWithPath: workspaceRoot)

        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = path + ":/opt/homebrew/bin:/usr/local/bin"
        }
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe

        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.process = proc

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.handleIncomingData(data)
            }
        }

        try proc.run()
        self.isRunning = true
    }

    public func setNotificationHandler(_ handler: @escaping (String, [String: Any]) -> Void) {
        self.notificationHandler = handler
    }

    public func sendNotification(method: String, params: [String: Any] = [:]) throws {
        guard isRunning, let inPipe = stdinPipe else {
            throw MuseCodeCLIError.executionFailed(exitCode: -1, stderr: "MSP host process not running")
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        var lineData = jsonData
        lineData.append(Data([0x0A]))
        inPipe.fileHandleForWriting.write(lineData)
    }

    public func sendCommand(method: String, params: [String: Any]) async throws -> [String: Any] {
        guard isRunning, let inPipe = stdinPipe else {
            throw MuseCodeCLIError.executionFailed(exitCode: -1, stderr: "MSP host process not running")
        }

        let reqId = UUID().uuidString
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": reqId,
            "method": method,
            "params": params
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        var lineData = jsonData
        lineData.append(Data([0x0A])) // newline delimitation

        let responseString = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            pendingContinuations[reqId] = continuation
            inPipe.fileHandleForWriting.write(lineData)
        }

        if let data = responseString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return [:]
    }

    private func handleIncomingData(_ data: Data) {
        incomingBuffer.append(data)

        let newlineDelimiter = Data([0x0A]) // '\n'
        while let range = incomingBuffer.range(of: newlineDelimiter) {
            let lineData = incomingBuffer.subdata(in: 0..<range.lowerBound)
            incomingBuffer.removeSubrange(0..<range.upperBound)

            guard !lineData.isEmpty,
                  let lineString = String(data: lineData, encoding: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if let id = json["id"] as? String {
                if let cont = pendingContinuations.removeValue(forKey: id) {
                    if let error = json["error"] as? [String: Any] {
                        let msg = error["message"] as? String ?? "MSP RPC Error"
                        cont.resume(throwing: MuseCodeCLIError.executionFailed(exitCode: -1, stderr: msg))
                    } else if let result = json["result"] {
                        if let resData = try? JSONSerialization.data(withJSONObject: result),
                           let resStr = String(data: resData, encoding: .utf8) {
                            cont.resume(returning: resStr)
                        } else {
                            cont.resume(returning: lineString)
                        }
                    } else {
                        cont.resume(returning: lineString)
                    }
                }
            } else if let method = json["method"] as? String {
                let params = json["params"] as? [String: Any] ?? [:]
                notificationHandler?(method, params)
            }
        }
    }

    public func stopHost() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        isRunning = false
        pendingContinuations.removeAll()
    }
}
