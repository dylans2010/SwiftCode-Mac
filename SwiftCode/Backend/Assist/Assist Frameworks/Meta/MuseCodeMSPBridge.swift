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
    public let params: AnyCodable?
    public let result: AnyCodable?
    public let error: AnyCodable?

    public init(jsonrpc: String = "2.0", id: String? = nil, method: String? = nil, params: AnyCodable? = nil, result: AnyCodable? = nil, error: AnyCodable? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }
}

public struct AnyCodable: Codable, @unchecked Sendable {
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
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
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
            let encodableArray = array.map { AnyCodable($0) }
            try container.encode(encodableArray)
        } else if let dictionary = value as? [String: Any] {
            var encodableDict = [String: AnyCodable]()
            for (k, v) in dictionary {
                encodableDict[k] = AnyCodable(v)
            }
            try container.encode(encodableDict)
        } else {
            try container.encodeNil()
        }
    }
}

public actor MuseCodeMSPBridge {
    public static let shared = MuseCodeMSPBridge()

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var isRunning: Bool = false
    private var pendingContinuations: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var notificationHandler: ((String, [String: Any]) -> Void)?
    private var incomingBuffer = Data()

    private init() {}

    public func startHost(workspaceRoot: String) async throws {
        guard !isRunning else { return }

        guard let executablePath = await MuseCodeCLIHelper.shared.discoverExecutablePath() else {
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
            Task { [weak self] in
                await self?.handleIncomingData(data)
            }
        }

        try proc.run()
        self.isRunning = true
    }

    public func setNotificationHandler(_ handler: @escaping (String, [String: Any]) -> Void) {
        self.notificationHandler = handler
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

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations[reqId] = continuation
            inPipe.fileHandleForWriting.write(lineData)
        }
    }

    private func handleIncomingData(_ data: Data) {
        incomingBuffer.append(data)

        let newlineDelimiter = Data([0x0A]) // '\n'
        while let range = incomingBuffer.range(of: newlineDelimiter) {
            let lineData = incomingBuffer.subdata(in: 0..<range.lowerBound)
            incomingBuffer.removeSubrange(0..<range.upperBound)

            guard !lineData.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if let id = json["id"] as? String {
                if let cont = pendingContinuations.removeValue(forKey: id) {
                    if let error = json["error"] as? [String: Any] {
                        let msg = error["message"] as? String ?? "MSP RPC Error"
                        cont.resume(throwing: MuseCodeCLIError.executionFailed(exitCode: -1, stderr: msg))
                    } else if let result = json["result"] as? [String: Any] {
                        cont.resume(returning: result)
                    } else {
                        cont.resume(returning: json)
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
