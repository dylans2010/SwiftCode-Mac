import Foundation

public enum OpenRouterSDKToolSource: String, Sendable {
    case swiftcode
    case openrouter
    case combined
}

public struct OpenRouterSDKHistoryItem: Sendable {
    public let role: String
    public let text: String
    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

public struct OpenRouterSDKToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let parametersJSON: String
    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

public struct OpenRouterSDKRunConfig: Sendable {
    public let maxSteps: Int
    public let maxCost: Double
    public let toolTimeoutMs: Int
    public let perRequestTimeoutMs: Int
    public let allowFinalResponse: Bool
    public init(
        maxSteps: Int = 25,
        maxCost: Double = 2.0,
        toolTimeoutMs: Int = 120_000,
        perRequestTimeoutMs: Int = 90_000,
        allowFinalResponse: Bool = true
    ) {
        self.maxSteps = maxSteps
        self.maxCost = maxCost
        self.toolTimeoutMs = toolTimeoutMs
        self.perRequestTimeoutMs = perRequestTimeoutMs
        self.allowFinalResponse = allowFinalResponse
    }
}

public struct OpenRouterSDKRunRequest: Sendable {
    public let model: String
    public let systemPrompt: String
    public let userText: String
    public let history: [OpenRouterSDKHistoryItem]
    public let tools: [OpenRouterSDKToolDefinition]
    public let toolSource: OpenRouterSDKToolSource
    public let config: OpenRouterSDKRunConfig
    public let requestId: String

    public init(
        model: String,
        systemPrompt: String,
        userText: String,
        history: [OpenRouterSDKHistoryItem] = [],
        tools: [OpenRouterSDKToolDefinition] = [],
        toolSource: OpenRouterSDKToolSource,
        config: OpenRouterSDKRunConfig = OpenRouterSDKRunConfig(),
        requestId: String = UUID().uuidString
    ) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.userText = userText
        self.history = history
        self.tools = tools
        self.toolSource = toolSource
        self.config = config
        self.requestId = requestId
    }
}

public enum OpenRouterSDKProviderError: LocalizedError, Sendable {
    case invalidRunRequest(String)
    case missingAPIKey
    case bridgeNotReady(String)
    case bridgeFailed(String)
    case bridgeExited(Int32)
    case cancelled
    case noToolExecutor(toolName: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRunRequest(let detail):
            return detail
        case .missingAPIKey:
            return "No OpenRouter API key found. Add one in Assist Settings (API Keys), then try again."
        case .bridgeNotReady(let detail):
            return detail
        case .bridgeFailed(let detail):
            return detail
        case .bridgeExited(let code):
            return "OpenRouter SDK bridge exited with status \(code)."
        case .cancelled:
            return "OpenRouter run cancelled."
        case .noToolExecutor(let toolName):
            return "No SwiftCode tool executor is configured, so tool \"\(toolName)\" cannot run. The call failed closed instead of being faked."
        }
    }
}

public actor OpenRouterSDKProvider {
    private let launcher: SDKBridgeLaunching
    private let scriptPath: String

    private var session: SDKBridgeSession?
    private var lineContinuation: AsyncStream<String>.Continuation?
    private var cancelled = false

    public init(
        launcher: SDKBridgeLaunching = FoundationProcessBridgeLauncher(),
        scriptPath: String
    ) {
        self.launcher = launcher
        self.scriptPath = scriptPath
    }

    public func run(
        _ request: OpenRouterSDKRunRequest,
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
        cancelled = true
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
        _ request: OpenRouterSDKRunRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        onToolEvent: @escaping @Sendable (SDKToolEvent) -> Void,
        executeTool: (@Sendable (String, String, String) async throws -> String)?
    ) async throws {
        guard session == nil else {
            throw OpenRouterSDKProviderError.bridgeFailed(
                "An OpenRouter SDK run is already active on this provider instance. "
                + "Cancel it or use a separate provider instance for a concurrent run."
            )
        }
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !model.contains(where: { $0.isWhitespace }) else {
            throw OpenRouterSDKProviderError.invalidRunRequest(
                "The selected model id is empty or malformed. Select an OpenRouter model "
                + "(provider/model) in Assist Settings; no substitute model was chosen."
            )
        }
        guard !request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterSDKProviderError.invalidRunRequest(
                "No system prompt was supplied. SwiftCode's real system prompt is required; "
                + "a generic prompt is never substituted."
            )
        }
        guard !request.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterSDKProviderError.invalidRunRequest("No user text was supplied for this run.")
        }

        var toolsPayload: [[String: Any]] = []
        for tool in request.tools {
            guard let data = tool.parametersJSON.data(using: .utf8),
                  let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw OpenRouterSDKProviderError.invalidRunRequest(
                    "Tool \"\(tool.name)\" has a malformed parameters schema. Fix the schema; "
                    + "it is never silently replaced with an empty one."
                )
            }
            toolsPayload.append(["name": tool.name, "description": tool.description, "parameters": schema])
        }

        let apiKey = await MainActor.run { OpenRouterClient.resolveOpenRouterAPIKey() }
        guard !apiKey.isEmpty else {
            throw OpenRouterSDKProviderError.missingAPIKey
        }

        let bridge: SDKBridgeSession
        do {
            bridge = try await launcher.launchBridge(provider: "openrouter", scriptPath: scriptPath, arguments: [])
        } catch {
            throw OpenRouterSDKProviderError.bridgeFailed("Failed to launch the OpenRouter SDK bridge: \(error.localizedDescription)")
        }
        self.session = bridge
        cancelled = false

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
        nonisolated(unsafe) var iterator = lineStream.makeAsyncIterator()

        let ready = try await waitForReady(stream: lineStream, bridge: bridge)
        guard ready else {
            let tail = bridge.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            cleanup(bridge: bridge)
            throw OpenRouterSDKProviderError.bridgeNotReady(
                "OpenRouter SDK bridge did not report ready within 30 seconds. "
                + "Check that Node.js and the SDK runtime are installed (Assist Settings → SDK runtime), then try again."
                + (tail.isEmpty ? "" : " Bridge stderr: \(tail)")
            )
        }

        let runPayload: [String: Any] = [
            "type": "run",
            "requestId": request.requestId,
            "provider": "openrouter",
            "model": model,
            "systemPrompt": request.systemPrompt,
            "userText": request.userText,
            "history": request.history.map { ["role": $0.role, "text": $0.text] },
            "tools": toolsPayload,
            "toolSource": request.toolSource.rawValue,
            "apiKey": apiKey,
            "config": [
                "maxSteps": request.config.maxSteps,
                "maxCost": request.config.maxCost,
                "toolTimeoutMs": request.config.toolTimeoutMs,
                "perRequestTimeoutMs": request.config.perRequestTimeoutMs,
                "allowFinalResponse": request.config.allowFinalResponse,
            ] as [String: Any],
        ]
        let runData = try JSONSerialization.data(withJSONObject: runPayload, options: [])
        guard let runLine = String(data: runData, encoding: .utf8) else {
            cleanup(bridge: bridge)
            throw OpenRouterSDKProviderError.bridgeFailed("Failed to encode the OpenRouter run request.")
        }
        bridge.writeLine(runLine)

        while let line = await iterator.next() {
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
                let argsString = jsonString(from: json["arguments"]) ?? "{}"
                let resultLine: String
                do {
                    guard let executeTool else {
                        throw OpenRouterSDKProviderError.noToolExecutor(toolName: name)
                    }
                    let resultText = try await executeTool(callId, name, argsString)
                    let resultValue = jsonValue(from: resultText) ?? resultText
                    let payload: [String: Any] = ["type": "tool_result", "id": callId, "result": resultValue]
                    resultLine = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? ""
                } catch {
                    let payload: [String: Any] = ["type": "tool_result", "id": callId, "error": error.localizedDescription]
                    resultLine = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? ""
                }
                if !resultLine.isEmpty {
                    bridge.writeLine(resultLine)
                }
            case "done":
                cleanup(bridge: bridge)
                continuation.finish()
                return
            case "error":
                let message = json["message"] as? String ?? "Unknown OpenRouter bridge error."
                cleanup(bridge: bridge)
                if cancelled {
                    throw OpenRouterSDKProviderError.cancelled
                }
                throw OpenRouterSDKProviderError.bridgeFailed(message)
            default:
                continue
            }
        }

        cleanup(bridge: bridge)
        if cancelled {
            throw OpenRouterSDKProviderError.cancelled
        }
        if bridge.process.isRunning == false, bridge.process.terminationStatus != 0 {
            throw OpenRouterSDKProviderError.bridgeExited(bridge.process.terminationStatus)
        }
        throw OpenRouterSDKProviderError.bridgeFailed(
            "OpenRouter SDK bridge closed without a done or error line. Check the SDK runtime installation and try again."
        )
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
                        guard version == SDKProvider.openRouter.pinnedVersion else {
                            throw OpenRouterSDKProviderError.bridgeFailed(
                                "OpenRouter bridge reported SDK version \"\(version)\", expected \(SDKProvider.openRouter.pinnedVersion). " +
                                "Reinstall the SDK runtime in Assist Settings → SDK Providers.")
                        }
                        return true
                    }
                    if type == "error" {
                        throw OpenRouterSDKProviderError.bridgeFailed(
                            json["message"] as? String ?? "OpenRouter bridge failed before ready.")
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
        case "pending", "requested": state = .requested
        case "running": state = .running
        case "completed": state = .completed
        case "failed": state = .failed
        case "cancelled": state = .cancelled
        default: return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func dateField(_ key: String) -> Date? {
            guard let raw = json[key] as? String, !raw.isEmpty else { return nil }
            return fractional.date(from: raw) ?? plain.date(from: raw)
        }
        let error = (json["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return SDKToolEvent(
            provider: provider,
            sessionId: sessionId,
            toolCallId: toolCallId,
            toolName: toolName,
            source: source,
            state: state,
            arguments: jsonString(from: json["arguments"]) ?? "",
            result: jsonString(from: json["result"]),
            error: error,
            startedAt: dateField("startedAt"),
            completedAt: dateField("completedAt")
        )
    }

    private func jsonString(from value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if value is NSNull { return nil }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func jsonValue(from text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
