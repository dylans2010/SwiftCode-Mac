import Foundation

public enum OpenCodeSDKToolSource: String, Sendable {
    case swiftcode
    case opencode
    case combined
}

public final class SDKBridgeSession: @unchecked Sendable {
    public let process: Process
    public let standardInput: Pipe
    public let standardOutput: Pipe
    public let standardError: Pipe?
    public var stderrTail = ""

    public init(process: Process, standardInput: Pipe, standardOutput: Pipe, standardError: Pipe? = nil) {
        self.process = process
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public func writeLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        standardInput.fileHandleForWriting.write(data)
    }

    public func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}

public protocol SDKBridgeLaunching: Sendable {
    func launchBridge(provider: String, scriptPath: String, arguments: [String]) async throws -> SDKBridgeSession
}

public struct FoundationProcessBridgeLauncher: SDKBridgeLaunching, Sendable {
    public init() {}

    public func launchBridge(provider: String, scriptPath: String, arguments: [String]) async throws -> SDKBridgeSession {
        let process = Process()
        var nodePath: String?
        if let detected = SDKRuntimeManager.detectRuntime(), detected.kind == .node {
            nodePath = detected.path
        }
        if let nodePath {
            process.executableURL = URL(fileURLWithPath: nodePath)
            process.arguments = [scriptPath] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", scriptPath] + arguments
        }
        process.currentDirectoryURL = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
        var environment: [String: String] = [:]
        let parent = ProcessInfo.processInfo.environment
        var pathValue = parent["PATH"] ?? ""
        if let nodePath {
            let binDir = (nodePath as NSString).deletingLastPathComponent
            pathValue = pathValue.isEmpty ? binDir : "\(binDir):\(pathValue)"
        }
        if !pathValue.isEmpty { environment["PATH"] = pathValue }
        if let home = parent["HOME"] { environment["HOME"] = home }
        if let tmp = parent["TMPDIR"] { environment["TMPDIR"] = tmp }
        environment["NODE_NO_WARNINGS"] = "1"
        process.environment = environment
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let session = SDKBridgeSession(process: process, standardInput: stdin, standardOutput: stdout, standardError: stderr)
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else { return }
            session.stderrTail += text
            if session.stderrTail.count > 8192 {
                session.stderrTail = String(session.stderrTail.suffix(8192))
            }
        }
        return session
    }
}

public struct OpenCodeSDKHistoryItem: Sendable {
    public let role: String
    public let text: String
    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

public struct OpenCodeSDKToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let parametersJSON: String
    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

public struct OpenCodeSDKRunRequest: Sendable {
    public let model: String
    public let systemPrompt: String
    public let userText: String
    public let history: [OpenCodeSDKHistoryItem]
    public let tools: [OpenCodeSDKToolDefinition]
    public let toolSource: OpenCodeSDKToolSource
    public let directory: String
    public let sessionId: String?
    public let agentName: String

    public init(
        model: String,
        systemPrompt: String,
        userText: String,
        history: [OpenCodeSDKHistoryItem] = [],
        tools: [OpenCodeSDKToolDefinition] = [],
        toolSource: OpenCodeSDKToolSource,
        directory: String,
        sessionId: String? = nil,
        agentName: String = OpenCodeConfiguration.defaultAgentName
    ) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.userText = userText
        self.history = history
        self.tools = tools
        self.toolSource = toolSource
        self.directory = directory
        self.sessionId = sessionId
        self.agentName = agentName
    }
}

public enum OpenCodeSDKProviderError: Error, Sendable {
    case invalidModelID(String)
    case bridgeNotReady(String)
    case bridgeFailed(String)
    case bridgeExited(Int32)
    case noToolExecutor(toolName: String)
}

public actor OpenCodeSDKProvider {
    private let launcher: SDKBridgeLaunching
    private let scriptPath: String
    private let configuration: OpenCodeConfiguration

    private var session: SDKBridgeSession?
    private var lineContinuation: AsyncStream<String>.Continuation?

    public init(
        launcher: SDKBridgeLaunching = FoundationProcessBridgeLauncher(),
        scriptPath: String,
        configuration: OpenCodeConfiguration = OpenCodeConfiguration.load()
    ) {
        self.launcher = launcher
        self.scriptPath = scriptPath
        self.configuration = configuration
    }

    public func run(
        _ request: OpenCodeSDKRunRequest,
        onToolEvent: @escaping @Sendable (SDKToolEvent) -> Void,
        executeTool: (@Sendable (String, String, String) async throws -> String)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.execute(request, continuation: continuation, onToolEvent: onToolEvent, executeTool: executeTool)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cancel() {
        if let session {
            session.writeLine(#"{"type":"cancel"}"#)
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                session.terminate()
            }
        }
        lineContinuation?.finish()
    }

    private func execute(
        _ request: OpenCodeSDKRunRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        onToolEvent: @escaping @Sendable (SDKToolEvent) -> Void,
        executeTool: (@Sendable (String, String, String) async throws -> String)?
    ) async throws {
        guard OpenCodeModelID.parse(request.model) != nil else {
            throw OpenCodeSDKProviderError.invalidModelID(
                "Invalid OpenCode model id \"\(request.model)\": expected \"opencode:<provider>/<model>\". " +
                "Select an OpenCode model in Assist Settings; SwiftCode never substitutes another model."
            )
        }

        var bridgeArgs = ["--server-url", configuration.serverURL.absoluteString]
        if configuration.managedServerEnabled || configuration.isLoopback {
            bridgeArgs.append("--managed")
        }

        let bridge: SDKBridgeSession
        do {
            bridge = try await launcher.launchBridge(provider: "opencode", scriptPath: scriptPath, arguments: bridgeArgs)
        } catch {
            throw OpenCodeSDKProviderError.bridgeFailed("Failed to launch the OpenCode SDK bridge: \(error.localizedDescription)")
        }
        self.session = bridge

        let (lineStream, lineContinuation) = AsyncStream<String>.makeStream()
        self.lineContinuation = lineContinuation
        let buffer = BufferWrapper()
        let outputHandle = bridge.standardOutput.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            while let newline = buffer.popLine() {
                if let line = String(data: newline, encoding: .utf8), !line.isEmpty {
                    lineContinuation.yield(line)
                }
            }
        }
        bridge.process.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }
        let ready = try await waitForReady(stream: lineStream, bridge: bridge)
        guard ready else {
            bridge.terminate()
            let tail = bridge.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            throw OpenCodeSDKProviderError.bridgeNotReady(
                "OpenCode SDK bridge did not report ready within 30 seconds. " +
                "Check that the SDK runtime is installed and the server is reachable, then try again." +
                (tail.isEmpty ? "" : " Bridge stderr: \(tail)")
            )
        }

        var runPayload: [String: Any] = [
            "type": "run",
            "requestId": UUID().uuidString,
            "provider": "opencode",
            "model": request.model,
            "systemPrompt": request.systemPrompt,
            "userText": request.userText,
            "history": request.history.map { ["role": $0.role, "text": $0.text] },
            "toolSource": request.toolSource.rawValue,
            "config": [
                "directory": request.directory,
                "agentName": request.agentName,
            ] as [String: Any],
        ]
        var toolsPayload: [[String: Any]] = []
        for tool in request.tools {
            let schema = (try? JSONSerialization.jsonObject(with: Data(tool.parametersJSON.utf8))) as? [String: Any] ?? [:]
            toolsPayload.append(["name": tool.name, "description": tool.description, "parameters": schema])
        }
        runPayload["tools"] = toolsPayload
        if let sessionId = request.sessionId {
            var config = runPayload["config"] as! [String: Any]
            config["sessionId"] = sessionId
            runPayload["config"] = config
        }
        let runData = try JSONSerialization.data(withJSONObject: runPayload, options: [])
        guard let runLine = String(data: runData, encoding: .utf8) else {
            throw OpenCodeSDKProviderError.bridgeFailed("Failed to encode the OpenCode run request.")
        }
        bridge.writeLine(runLine)

        for try await line in lineStream {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            switch type {
            case "text":
                if let delta = json["delta"] as? String, !delta.isEmpty {
                    continuation.yield(delta)
                }
            case "tool_event":
                if let eventJson = json["event"] as? [String: Any],
                   let event = decodeToolEvent(eventJson) {
                    onToolEvent(event)
                }
            case "tool_call":
                let callId = json["id"] as? String ?? ""
                let name = json["name"] as? String ?? ""
                let args = json["arguments"] as? String ?? "{}"
                onToolEvent(SDKToolEvent(
                    provider: "opencode",
                    sessionId: request.sessionId ?? "",
                    toolCallId: callId,
                    toolName: name,
                    source: .swiftcode,
                    state: .running,
                    arguments: args
                ))
                let resultLine: String
                do {
                    guard let executeTool else {
                        throw OpenCodeSDKProviderError.noToolExecutor(toolName: name)
                    }
                    let result = try await executeTool(callId, name, args)
                    onToolEvent(SDKToolEvent(
                        provider: "opencode",
                        sessionId: request.sessionId ?? "",
                        toolCallId: callId,
                        toolName: name,
                        source: .swiftcode,
                        state: .completed,
                        arguments: args,
                        result: result
                    ))
                    let payload: [String: Any] = ["type": "tool_result", "id": callId, "result": result]
                    resultLine = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? ""
                } catch {
                    onToolEvent(SDKToolEvent(
                        provider: "opencode",
                        sessionId: request.sessionId ?? "",
                        toolCallId: callId,
                        toolName: name,
                        source: .swiftcode,
                        state: .failed,
                        arguments: args,
                        error: error.localizedDescription
                    ))
                    let payload: [String: Any] = ["type": "tool_result", "id": callId, "error": error.localizedDescription]
                    resultLine = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? ""
                }
                if !resultLine.isEmpty {
                    bridge.writeLine(resultLine)
                }
            case "done":
                let final = json["finalText"] as? String ?? ""
                if !final.isEmpty {
                    _ = final
                }
                cleanup(bridge: bridge)
                continuation.finish()
                return
            case "error":
                let message = json["message"] as? String ?? "Unknown OpenCode bridge error."
                cleanup(bridge: bridge)
                throw OpenCodeSDKProviderError.bridgeFailed(message)
            default:
                continue
            }
        }

        cleanup(bridge: bridge)
        if bridge.process.isRunning == false, bridge.process.terminationStatus != 0 {
            throw OpenCodeSDKProviderError.bridgeExited(bridge.process.terminationStatus)
        }
        continuation.finish()
    }

    private func handleTermination() {
        lineContinuation?.finish()
        lineContinuation = nil
    }

    private func cleanup(bridge: SDKBridgeSession) {
        bridge.standardOutput.fileHandleForReading.readabilityHandler = nil
        bridge.standardError?.fileHandleForReading.readabilityHandler = nil
        lineContinuation?.finish()
        lineContinuation = nil
        try? bridge.standardInput.fileHandleForWriting.close()
        if session === bridge {
            session = nil
        }
    }

    private func waitForReady(stream: AsyncStream<String>, bridge: SDKBridgeSession) async throws -> Bool {
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                while let line = await iterator.next() {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else {
                        continue
                    }
                    if type == "ready" {
                        let version = json["sdkVersion"] as? String ?? ""
                        guard version == SDKProvider.openCode.pinnedVersion else {
                            throw OpenCodeSDKProviderError.bridgeFailed(
                                "OpenCode bridge reported SDK version \"\(version)\", expected \(SDKProvider.openCode.pinnedVersion). " +
                                "Reinstall the SDK runtime in Assist Settings → SDK Providers.")
                        }
                        return true
                    }
                    if type == "error" {
                        throw OpenCodeSDKProviderError.bridgeFailed(
                            json["message"] as? String ?? "OpenCode bridge failed before ready.")
                    }
                }
                return false
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                bridge.terminate()
                return false
            }
            let first = try await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func decodeToolEvent(_ json: [String: Any]) -> SDKToolEvent? {
        guard let provider = json["provider"] as? String,
              let sessionId = json["sessionId"] as? String,
              let toolCallId = json["toolCallId"] as? String,
              let toolName = json["toolName"] as? String,
              let sourceRaw = json["source"] as? String,
              let source = SDKToolSource(rawValue: sourceRaw),
              let stateRaw = json["state"] as? String else {
            return nil
        }
        let state: SDKToolState
        switch stateRaw {
        case "pending": state = .requested
        case "running": state = .running
        case "completed": state = .completed
        case "failed": state = .failed
        case "cancelled": state = .cancelled
        default: return nil
        }
        let iso = ISO8601DateFormatter()
        func dateField(_ key: String) -> Date? {
            guard let raw = json[key] as? String, !raw.isEmpty else { return nil }
            return iso.date(from: raw)
        }
        let result = (json["result"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let error = (json["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return SDKToolEvent(
            provider: provider,
            sessionId: sessionId,
            toolCallId: toolCallId,
            toolName: toolName,
            source: source,
            state: state,
            arguments: json["arguments"] as? String ?? "",
            result: result,
            error: error,
            startedAt: dateField("startedAt"),
            completedAt: dateField("completedAt")
        )
    }
}
