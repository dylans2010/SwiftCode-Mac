import Foundation

// MARK: - OpenRouter SDK provider (Swift facade over openrouter-bridge.mjs)
//
// This file NEVER executes tools and NEVER speaks OpenRouter HTTP itself.
// The previous OpenAI-compatible HTTP client (OpenRouterClient.swift) is
// superseded as the agent-execution transport by the real Agent SDK,
// which Swift cannot import: the SDK is TypeScript
// (@openrouter/agent@0.11.0). Swift therefore launches the Node bridge
// (SDKHosts/openrouter-bridge.mjs) and talks the shared NDJSON run
// protocol over its stdin/stdout. The bridge owns the SDK's multi-turn
// loop, stop conditions, and streaming; Swift owns the run lifecycle
// and, through the parent integration, the native tool registry that
// executes SwiftCode tool_call lines.
//
// INSTALL LAYOUT (Workstream D seam — read before changing paths):
// The bridge is a runtime resource, not an Xcode target member. The
// runtime manager installs it under Application Support at
//   <Application Support>/SwiftCode/SDKRuntime/openrouter/bridge/openrouter-bridge.mjs
// with the pinned packages at
//   <Application Support>/SwiftCode/SDKRuntime/openrouter/node_modules/@openrouter/agent
// (SDKRuntimeManager.bridgeDirectory / runtimeDirectory). Node resolves
// '@openrouter/agent' by walking up from the bridge file and via the
// NODE_PATH the manager sets, so the bridge MUST live inside that
// directory; copying the .mjs alone somewhere else breaks SDK
// resolution. The repo copy at
// SwiftCode/Backend/Assist/SDKHosts/openrouter-bridge.mjs is the source
// the manager copies from. This provider takes `scriptPath` as an init
// parameter so the parent integration can pass the manager's installed
// path; it never guesses a bundle location.
//
// LAUNCHER SEAM (single call, shared with Workstream A):
// This provider launches through `SDKBridgeLaunching.launchBridge(
// provider:scriptPath:arguments:)` (defined in OpenCodeSDKProvider.swift)
// with the default `FoundationProcessBridgeLauncher`. That launcher
// passes a controlled environment (PATH/HOME/TMPDIR) and NO key, so the
// API key travels in the run request's non-logged `apiKey` field —
// never argv, never logged, never echoed by the bridge. When the parent
// wires SDKRuntimeManager instead, the manager injects
// OPENROUTER_API_KEY into the bridge environment for the openRouter
// provider, and the bridge prefers the environment over the run field,
// so no bridge change is needed for that switch.
//
// READINESS vs AUTHENTICATION (do not conflate them):
// The bridge prints `ready` once the SDK imports resolve. That proves
// the SDK is installed and loadable; it does NOT prove the key is
// valid, because @openrouter/agent 0.11.0 has no cost-free key check.
// The first run's 401 is mapped by the bridge to an actionable invalid
// key error. Settings' connection test remains
// OpenRouterAssistProvider's /models check; this provider is execution.
//
// TOOL EVENTS — no synthetic duplicates:
// Unlike Workstream A's bridge, this bridge emits the FULL tool
// lifecycle (requested/running/completed/failed) for every call,
// including bridged SwiftCode calls. This provider therefore forwards
// bridge `tool_event` lines verbatim to `onToolEvent` and emits NO
// synthetic events for `tool_call` lines — the store merges by
// toolCallId, and a synthetic row would double-report the same call.
// Routing key is the event's `source` (SDKToolSource), never the name:
// in a combined run, `openrouter_`-prefixed host tools still carry
// source `.openrouter`, and SwiftCode tools carry `.swiftcode`.
//
// TOOL SOURCE (run-level) vs EVENT SOURCE (per-call):
// `OpenRouterSDKToolSource` has a `.combined` case, but Workstream C's
// `SDKToolSource` deliberately does not: a combined run produces events
// from two ecosystems, each tagged with its own source. `opencode` is
// NOT a valid OpenRouter tool source and is rejected before launch
// (the bridge rejects it too, as defense in depth).

/// Tool source selected for an OpenRouter SDK run. `opencode` is NOT a
/// valid OpenRouter tool source and has no case here by design.
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
    /// Raw JSON string of the parameters schema (a JSON object). Decoded
    /// here before launch; a malformed schema fails the run loudly
    /// instead of reaching the bridge as text.
    public let parametersJSON: String
    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

/// Run bounds. Defaults match the bridge defaults: at most 25 model
/// steps, a $2.00 maxCost STOP CONDITION (not a spending ceiling: the
/// SDK stops the loop after the step reaching it, then — with
/// allowFinalResponse — makes one final turn, so spend can exceed
/// $2.00), 120s per tool call, 90s per model request, and a final
/// text turn after a stop condition fires.
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
    /// Exact OpenRouter model id (provider/model). Validated before
    /// launch; never guessed or rewritten.
    public let model: String
    public let systemPrompt: String
    public let userText: String
    public let history: [OpenRouterSDKHistoryItem]
    public let tools: [OpenRouterSDKToolDefinition]
    public let toolSource: OpenRouterSDKToolSource
    public let config: OpenRouterSDKRunConfig
    /// Session id carried in every tool event. Defaults to a fresh UUID.
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

// MARK: - Provider

/// Swift facade for OpenRouter Agent SDK runs. One provider instance
/// serves one run at a time; `cancel()` aborts the active run and
/// terminates the bridge. Sequential runs on one instance are fine.
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

    /// Runs one request, streaming model text deltas. Tool activity is
    /// reported through `onToolEvent` (bridge tool_event lines, verbatim
    /// — see the header note on synthetic duplicates); SwiftCode-native
    /// tool_call lines are executed by `executeTool` (supplied by the
    /// parent integration, which routes through the native registry)
    /// and the result is fed back to the bridge. This provider itself
    /// executes nothing: if no executor is supplied, tool calls fail
    /// closed with an explicit error result instead of hanging or being
    /// faked. This provider never falls back to OpenRouterClient HTTP
    /// execution; the only OpenRouterClient use is key resolution.
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
            // Ask the bridge to abort the SDK run first (AbortSignal +
            // ModelResult.cancel()), then terminate the process; the
            // bridge exits cleanly on cancellation.
            session.writeLine(#"{"type":"cancel"}"#)
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                session.terminate()
            }
        }
        lineContinuation?.finish()
    }

    // MARK: - Execution

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

        // Tool schemas are decoded here; a malformed schema fails loudly
        // before any process is launched.
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

        // Key resolution only — credential retrieval, not execution.
        // The key is sent in the run payload's non-logged field (the
        // default launcher passes no key environment); the bridge never
        // logs or echoes it, and prefers a key environment when the
        // runtime manager provides one.
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

        // Stream stdout lines into an AsyncStream via readabilityHandler.
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
        // Keep the iterator alive for the run loop below. It is a
        // single-consumer local: no other task touches it, so the
        // actor-isolation region check (which flags every `await` on a
        // local mutable iterator as a send) is opted out of here.
        nonisolated(unsafe) var iterator = lineStream.makeAsyncIterator()

        // Readiness: the bridge prints {"type":"ready"} only after the
        // SDK imports resolve. Anything else first (an error line, EOF,
        // or 30 seconds of silence) is a failed connection — never a
        // successful one. Ready does NOT mean authenticated (see header).
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

        // Send the run request. The payload travels over stdin, never
        // argv, so no prompt, argument, or key appears in a process
        // listing. The bridge strips the key from every error it emits.
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

        // Consume bridge lines until done/error/process exit.
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
                // SwiftCode-native tool: execute through the parent's
                // executor (native registry), never here. The result —
                // or an explicit failure — goes back to the bridge so
                // the model continues with real data, not a guess. No
                // synthetic tool event is emitted here: the bridge
                // already emitted requested/running for this call id,
                // and emits completed/failed once the result lands.
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
                // Text deltas already streamed the answer; done only
                // signals completion. Do not re-yield finalText (that
                // would duplicate output).
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
        // The bridge exits on stdin EOF; close our write end so it can
        // shut down. Never kill an external process: the bridge is the
        // only process this provider owns.
        try? bridge.standardInput.fileHandleForWriting.close()
        if session === bridge {
            session = nil
        }
    }

    /// Waits for the bridge's ready line, with a 30-second timeout and
    /// early failure on an error line or EOF. Returns false on timeout.
    /// Ready lines are consumed from the stream's shared storage, and
    /// the run loop below ignores any stray "ready" line anyway, so
    /// either consumption outcome is safe.
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
                // EOF before ready: the bridge died; report as timeout
                // rather than hanging the caller.
                return false
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                // Terminate, don't just return: AsyncStream next() is
                // not cancellation-aware, so returning alone would
                // leave the group waiting on the suspended consumer.
                // The bridge's termination handler finishes the line
                // continuation, unblocking it.
                bridge.terminate()
                return false
            }
            let first = try await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Decodes a bridge tool_event object into the shared contract.
    /// Unlike Workstream A's bridge (which sends arguments/result as
    /// strings), this bridge sends them as JSON values, so values are
    /// rendered to compact JSON strings here; a plain string value
    /// passes through unchanged. Timestamps are ISO 8601 with or
    /// without fractional seconds; an empty or unparseable timestamp
    /// is never invented.
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

    /// Renders a decoded JSON value as a compact JSON string. A String
    /// value passes through unchanged (it is already the display form);
    /// NSNull and missing values become nil.
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

    /// Parses JSON text back into a value for a tool_result line.
    /// Returns nil when the text is not valid JSON (the caller then
    /// sends the raw string instead).
    private func jsonValue(from text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
