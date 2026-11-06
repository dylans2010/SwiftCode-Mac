import Foundation

// MARK: - Muse other-models bridge (Wave 16, Slice B)
//
// Ported from Legacy (Dylan's own code; direct port authorised
// under MIT):
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MuseOtherModelsBridge.swift`
//     — the bridge that lets the Meta Muse SDK session run on
//     third-party / custom / cloud models instead of Meta's own.
//
// What it bridges, verified live from Legacy @ d51a8f0d: the
// Muse SDK host is pointed at a local loopback proxy
// (`muse serve --base-url http://127.0.0.1:<port>`). The proxy
// answers the host's model catalog (`/muse-code/models`,
// `/models`, `/v1/models`) with the resolved other model, and
// translates the host's `/responses` (or `/v1/responses`,
// `/chat/completions`) calls into streaming completions from
// that model, as `response.output_text.delta` SSE events. The
// full Muse SDK architecture is preserved; only the model
// behind it changes.
//
// What is deliberately different from Legacy:
//   * NO `NWListener` / Network framework: the proxy is built
//     on SwiftCode's portable `LoopbackServer` (BSD sockets, already
//     in this target), so it stays Linux-buildable. The default
//     port is still 19855 when free (Legacy's), otherwise any
//     free loopback port — `LoopbackServer` binds port 0 by
//     default and reports the real one.
//   * NO `LLMService`, `AssistModelDiscoveryService`,
//     `CustomEndpointManager`, `SCCloudModelDiscovery`, or
//     `AppSettings` singletons: model resolution is pure over
//     injected inputs. The host supplies the discovered
//     candidates (as `AssistCandidateModel`s — the router's own
//     type), the custom endpoints, and the cloud model ids; the
//     bridge never reads a discovery service or settings store.
//     The free-only filter is Legacy's
//     `AssistModelEligibilityPolicy` (already in this target).
//   * The catalog entry is Legacy's verbatim shape (one model,
//     `muse-code` metadata, context 128,000, output 16,384,
//     `reasoningEffort: "high"`, `tool_call: true`).
//   * The SSE translation streams through an injected
//     `streamChat` closure: the host routes the resolved model
//     through SwiftCode's own provider dispatch
//     (`AssistantBackends.provider(forModelID:)`), which is the
//     SwiftCode equivalent of Legacy's `LLMService.streamChat`. The
//     bridge never picks a provider itself and never reroutes a
//     turn to another model.
//   * NOT ported: `MuseOtherModelsBridge.executeTurn` as a
//     direct LLM turn. Legacy's version streamed from
//     `LLMService`, parsed ```tool_call blocks out of the text,
//     and executed them through `AssistManager` — including the
//     Autopilot rule that bypassed approvals entirely. None of
//     those engines exists in SwiftCode, and the approval bypass
//     must not be recreated. The SwiftCode equivalent is the proxy
//     path (the MSP host streams through the other model) plus
//     the host router's failover. What survives from that
//     method as portable, testable pieces: the `<think>` token
//     splitter (`MuseThinkingTokenizer`, Legacy's
//     `GenerationState.processToken`) and the ```tool_call
//     block parser (`MuseToolCallParser`, Legacy's
//     `parseAndExecuteToolCalls` minus the execution — parsing
//     only, names normalized through `MetaToolNameNormalizer`).
//   * Wave 17, Slice B: the proxy lifecycle now has an owner
//     (`MuseOtherModelsProxyController`, at the end of this
//     file). `MuseLocalProxyServer.start` falls back to any
//     free loopback port when the requested one is taken
//     (Legacy's `NWListener(..., on: .any)`) and restarts when
//     the active model changes instead of returning a stale
//     proxy for the old model.

// MARK: - Model resolution

/// One non-Meta model the Muse SDK session may run on (Legacy
/// `AssistAvailableModel`, reduced to the fields resolution
/// reads — the full candidate type is `AssistCandidateModel`).
public struct MuseOtherModel: Sendable, Equatable {
    public let id: String
    public let displayName: String
    /// The provider-side model identifier.
    public let modelIdentifier: String
    public let providerName: String
    public let supportsToolCalling: Bool
    public let supportsAgenticUse: Bool

    public init(
        id: String,
        displayName: String? = nil,
        modelIdentifier: String? = nil,
        providerName: String,
        supportsToolCalling: Bool = true,
        supportsAgenticUse: Bool = true
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.modelIdentifier = modelIdentifier ?? id
        self.providerName = providerName
        self.supportsToolCalling = supportsToolCalling
        self.supportsAgenticUse = supportsAgenticUse
    }

    public init(candidate: AssistCandidateModel) {
        self.init(
            id: candidate.id,
            displayName: candidate.displayName,
            modelIdentifier: candidate.modelIdentifier,
            providerName: candidate.provider.displayName,
            supportsToolCalling: candidate.supportsToolCalling,
            supportsAgenticUse: candidate.supportsAgenticUse
        )
    }
}

/// One custom endpoint (Legacy `CustomEndpointManager` endpoint,
/// reduced to what resolution reads).
public struct MuseCustomEndpoint: Sendable, Equatable {
    public let name: String
    public let models: [String]
    public let isLocal: Bool
    public init(name: String, models: [String], isLocal: Bool = false) {
        self.name = name
        self.models = models
        self.isLocal = isLocal
    }
}

/// The resolved model for a Muse SDK session (Legacy
/// `resolveActiveModel`'s tuple).
public struct MuseOtherModelResolution: Sendable, Equatable {
    public let modelID: String
    public let displayName: String
    public let provider: String
    public init(modelID: String, displayName: String, provider: String) {
        self.modelID = modelID
        self.displayName = displayName
        self.provider = provider
    }
}

public enum MuseOtherModelsBridge {
    /// Fallback catalog when nothing is discovered (Legacy
    /// `availableOtherModels`): one free fallback, or the five
    /// paid fallbacks. Legacy's exact ids, display names and
    /// providers.
    public static let freeFallback = MuseOtherModel(
        id: "openrouter/free", displayName: "OpenRouter Free",
        modelIdentifier: "openrouter/free", providerName: "OpenRouter")
    public static let paidFallbacks: [MuseOtherModel] = [
        MuseOtherModel(id: "gpt-4o", displayName: "OpenAI GPT-4o", modelIdentifier: "gpt-4o", providerName: "OpenAI"),
        MuseOtherModel(id: "gpt-4o-mini", displayName: "OpenAI GPT-4o mini", modelIdentifier: "gpt-4o-mini", providerName: "OpenAI"),
        MuseOtherModel(id: "claude-3-7-sonnet-20250219", displayName: "Claude 3.7 Sonnet",
                       modelIdentifier: "claude-3-7-sonnet-20250219", providerName: "Anthropic"),
        MuseOtherModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", modelIdentifier: "gemini-2.5-pro", providerName: "Google Gemini"),
        MuseOtherModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", modelIdentifier: "gemini-2.5-flash", providerName: "Google Gemini"),
    ]

    /// Discovers the other models available for the Meta SDK
    /// (Legacy `availableOtherModels`): discovered candidates
    /// minus native Meta models (`meta_assist` provider, `muse-`
    /// prefix), plus custom-endpoint models, plus cloud models,
    /// then the free-only filter, then the fallbacks when empty.
    public static func availableOtherModels(
        discovered: [AssistCandidateModel],
        customEndpoints: [MuseCustomEndpoint] = [],
        cloudModelIDs: [String] = [],
        onlyUseFree: Bool = false
    ) -> [MuseOtherModel] {
        var models = discovered
            .filter { $0.provider != .metaAssist && !$0.modelIdentifier.hasPrefix("muse-") }
            .map { MuseOtherModel(candidate: $0) }

        for endpoint in customEndpoints {
            for modelID in endpoint.models where !models.contains(where: { $0.modelIdentifier == modelID }) {
                models.append(MuseOtherModel(
                    id: modelID,
                    displayName: "\(endpoint.name): \(modelID)",
                    modelIdentifier: modelID,
                    providerName: endpoint.name.isEmpty ? "Custom Model" : endpoint.name))
            }
        }

        for cloudID in cloudModelIDs where !models.contains(where: { $0.modelIdentifier == cloudID || $0.id == cloudID }) {
            models.append(MuseOtherModel(
                id: cloudID,
                displayName: "SwiftCode Cloud: \(cloudID)",
                modelIdentifier: cloudID,
                providerName: "SwiftCode Cloud"))
        }
        // Legacy always listed the default cloud model when no
        // cloud model was discovered.
        if cloudModelIDs.isEmpty, !models.contains(where: { $0.modelIdentifier == SCCloudProvider.internalIDPrefix || $0.id == SCCloudProvider.internalIDPrefix }) {
            models.append(MuseOtherModel(
                id: SCCloudProvider.internalIDPrefix,
                displayName: "SwiftCode Cloud Model",
                modelIdentifier: SCCloudProvider.internalIDPrefix,
                providerName: "SwiftCode Cloud"))
        }

        if onlyUseFree {
            models = models.filter {
                AssistModelEligibilityPolicy.isEligible(modelID: $0.modelIdentifier, onlyUseFreeModels: true)
            }
        }

        if models.isEmpty {
            models = onlyUseFree ? [freeFallback] : paidFallbacks
        }
        return models
    }

    /// Resolves the active model (Legacy `resolveActiveModel`,
    /// same five steps): 1. the user's explicitly selected
    /// other model; 2. the first custom endpoint's first
    /// eligible model; 3. the user's overall selected model when
    /// it is not a Meta model; 4. the first agent-compatible
    /// discovered model; 5. the reliable fallback.
    public static func resolveActiveModel(
        selectedOtherModelID: String,
        selectedOtherModelProvider: String = "",
        generalModelID: String = "",
        discovered: [AssistCandidateModel] = [],
        customEndpoints: [MuseCustomEndpoint] = [],
        cloudModelIDs: [String] = [],
        onlyUseFree: Bool = false
    ) -> MuseOtherModelResolution {
        // 1. Explicitly selected model for the Meta bridge.
        if !selectedOtherModelID.isEmpty {
            let modelID = selectedOtherModelID
            if SCCloudProvider.isCloudModelID(modelID) {
                let endpoint = SCCloudProvider.endpointName(forInternalID: modelID) ?? "swiftcode-cloud"
                return MuseOtherModelResolution(modelID: modelID, displayName: "SwiftCode Cloud: \(endpoint)", provider: "SwiftCode Cloud")
            }
            if !onlyUseFree || AssistModelEligibilityPolicy.isEligible(modelID: modelID, onlyUseFreeModels: true) {
                if let custom = customEndpoints.first(where: { $0.models.contains(modelID) }) {
                    return MuseOtherModelResolution(modelID: modelID, displayName: "\(custom.name): \(modelID)", provider: "Custom Model Setup")
                }
                if let found = discovered.first(where: { $0.modelIdentifier == modelID }) {
                    return MuseOtherModelResolution(modelID: modelID, displayName: found.displayName, provider: found.provider.displayName)
                }
                let provider = selectedOtherModelProvider.isEmpty
                    ? AssistModelSpecification.specification(for: modelID).provider.displayName
                    : selectedOtherModelProvider
                return MuseOtherModelResolution(modelID: modelID, displayName: modelID, provider: provider)
            }
        }

        // 2. First custom endpoint's first eligible model.
        if let firstEndpoint = customEndpoints.first {
            let eligible = AssistModelEligibilityPolicy.filterEligibleModelIDs(firstEndpoint.models, onlyUseFreeModels: onlyUseFree)
            if let firstModel = eligible.first {
                return MuseOtherModelResolution(modelID: firstModel, displayName: "\(firstEndpoint.name): \(firstModel)", provider: "Custom Model Setup")
            }
        }

        // 3. The user's overall selected model, when not Meta.
        if !generalModelID.isEmpty, !generalModelID.hasPrefix("muse-") {
            if SCCloudProvider.isCloudModelID(generalModelID) {
                let endpoint = SCCloudProvider.endpointName(forInternalID: generalModelID) ?? "swiftcode-cloud"
                return MuseOtherModelResolution(modelID: generalModelID, displayName: "SwiftCode Cloud: \(endpoint)", provider: "SwiftCode Cloud")
            }
            if !onlyUseFree || AssistModelEligibilityPolicy.isEligible(modelID: generalModelID, onlyUseFreeModels: true) {
                if let found = discovered.first(where: { $0.modelIdentifier == generalModelID }) {
                    return MuseOtherModelResolution(modelID: generalModelID, displayName: found.displayName, provider: found.provider.displayName)
                }
                return MuseOtherModelResolution(
                    modelID: generalModelID, displayName: generalModelID,
                    provider: AssistModelSpecification.specification(for: generalModelID).provider.displayName)
            }
        }

        // 4. First agent-compatible discovered model.
        let available = availableOtherModels(
            discovered: discovered, customEndpoints: customEndpoints,
            cloudModelIDs: cloudModelIDs, onlyUseFree: onlyUseFree)
        if let best = available.first(where: { $0.supportsAgenticUse && $0.supportsToolCalling }) ?? available.first {
            return MuseOtherModelResolution(modelID: best.modelIdentifier, displayName: best.displayName, provider: best.providerName)
        }

        // 5. Default reliable fallback.
        return onlyUseFree
            ? MuseOtherModelResolution(modelID: "openrouter/free", displayName: "OpenRouter Free", provider: "OpenRouter")
            : MuseOtherModelResolution(modelID: "gpt-4o", displayName: "OpenAI GPT-4o", provider: "OpenAI")
    }
}

// MARK: - Thinking tokenizer

/// Splits a token stream into thinking and text deltas
/// (Legacy `GenerationState.processToken`): `<think>` tags from
/// reasoning models open/close a thinking block; tokens inside
/// it are thinking, the rest are text. Thread-safe; `cancel()`
/// stops delivery.
public final class MuseThinkingTokenizer: @unchecked Sendable {
    private let lock = NSLock()
    private var fullText = ""
    private var isInThinkingBlock = false
    private var currentThinking = ""
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }
    public func cancel() { lock.withLock { cancelled = true } }
    public var text: String { lock.withLock { fullText } }
    public var thinking: String { lock.withLock { currentThinking } }

    /// Processes one token. Exactly one of the two callbacks
    /// fires per token (or neither, when cancelled).
    public func processToken(
        _ token: String,
        onThinkingDelta: ((String) -> Void)?,
        onTextDelta: (String) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }
        fullText += token

        if token.contains("<think>") {
            isInThinkingBlock = true
            let cleaned = token.replacingOccurrences(of: "<think>", with: "")
            if !cleaned.isEmpty {
                currentThinking += cleaned
                onThinkingDelta?(cleaned)
            }
            return
        } else if token.contains("</think>") {
            isInThinkingBlock = false
            let parts = token.components(separatedBy: "</think>")
            if let thoughtPart = parts.first, !thoughtPart.isEmpty {
                currentThinking += thoughtPart
                onThinkingDelta?(thoughtPart)
            }
            if parts.count > 1 {
                let textPart = parts[1]
                if !textPart.isEmpty {
                    onTextDelta(textPart)
                }
            }
            return
        }

        if isInThinkingBlock {
            currentThinking += token
            onThinkingDelta?(token)
        } else {
            onTextDelta(token)
        }
    }
}

// MARK: - Tool-call block parser

/// One parsed tool call (Legacy
/// `MuseOtherModelsBridge.ToolExecutionSummary`, minus the
/// executed output — parsing only).
public struct MuseParsedToolCall: Sendable, Equatable {
    public let toolName: String
    public let argumentsJSON: String
    public init(toolName: String, argumentsJSON: String) {
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }
}

/// Parses ```tool_call JSON blocks out of model text (Legacy
/// `parseAndExecuteToolCalls`, parsing half only). Names are
/// normalized through `MetaToolNameNormalizer` against the
/// injected MCP ids; execution is the host's job, never this
/// parser's. Returns [] unless the text contains a
/// ```tool_call or `<tool_call>` marker.
public enum MuseToolCallParser {
    public static func parse(_ text: String, knownToolIDs: Set<String> = []) -> [MuseParsedToolCall] {
        guard text.contains("```tool_call") || text.contains("<tool_call>") else { return [] }
        let pattern = "```tool_call\\s*([\\s\\S]*?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        var results: [MuseParsedToolCall] = []
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let callJson = nsText.substring(with: match.range(at: 1))
            guard let data = callJson.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawTool = dict["name"] as? String else { continue }
            let toolName = MetaToolNameNormalizer.normalize(rawTool, knownToolIDs: knownToolIDs).name
            let args: String
            if let arguments = dict["arguments"],
               JSONSerialization.isValidJSONObject(arguments),
               let argsData = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]),
               let argsText = String(data: argsData, encoding: .utf8) {
                args = argsText
            } else {
                args = "{}"
            }
            results.append(MuseParsedToolCall(toolName: toolName, argumentsJSON: args))
        }
        return results
    }
}

// MARK: - Local loopback proxy

/// The local HTTP translation proxy (Legacy
/// `MuseLocalProxyServer`, rebuilt on `LoopbackServer`).
///
/// Serves the resolved other model to the Muse SDK host:
///   * `/muse-code/models`, `/models`, `/v1/models` — the
///     dynamic catalog with the single active model (Legacy's
///     verbatim entry shape).
///   * `/responses`, `/v1/responses`, `/chat/completions` —
///     streams the model as `response.output_text.delta` SSE
///     events, then `response.completed`.
///   * Anything else — 404.
///
/// The token stream comes from the injected `streamChat`
/// closure: the host routes the resolved model through SwiftCode's
/// own provider dispatch. The proxy never picks a model or a
/// provider itself.
public final class MuseLocalProxyServer: @unchecked Sendable {
    /// Streams one chat's tokens: model id, messages, system
    /// prompt → the model's text tokens.
    public typealias StreamChat = @Sendable (String, [ChatMessage], String) -> AsyncThrowingStream<String, Error>

    /// Legacy's default port. The server binds it when free;
    /// otherwise `LoopbackServer` picks any free loopback port
    /// and `serverURL` reports the real one.
    public static let defaultPort: UInt16 = 19855

    private let lock = NSLock()
    private var server: LoopbackServer?
    private var _active: MuseOtherModelResolution?

    public init() {}

    public var isRunning: Bool { lock.withLock { server != nil } }
    public var serverURL: URL? { lock.withLock { server.map { URL(string: $0.baseURL)! } } }
    public var activeModel: MuseOtherModelResolution? { lock.withLock { _active } }

    /// The catalog entry for the active model (Legacy's verbatim
    /// shape: one model, `muse-code` metadata, context 128,000,
    /// output 16,384, `reasoningEffort: "high"`).
    public static func catalogJSON(for active: MuseOtherModelResolution) -> [String: Any] {
        [
            "object": "list",
            "data": [[
                "id": active.modelID,
                "object": "model",
                "created": Int(Date().timeIntervalSince1970),
                "owned_by": active.provider.lowercased(),
                "metadata": [
                    "muse-code": [
                        "name": active.modelID,
                        "family": "custom-bridge",
                        "release_date": "2026-10-12",
                        "is_hidden": false,
                        "attachment": true,
                        "reasoning": true,
                        "temperature": false,
                        "tool_call": true,
                        "modalities": ["input": ["text"], "output": ["text"]],
                        "limit": ["context": 128_000, "output": 16_384],
                        "options": ["reasoningEffort": "high"],
                    ],
                ],
            ]],
        ]
    }

    /// Parses a `/responses` (or `/chat/completions`) body into
    /// chat messages (Legacy's `processRequest`: `messages[]`
    /// first, else `input[]`; empty → a single "Hello").
    public static func parseRequestMessages(_ body: Data) -> [ChatMessage] {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return [ChatMessage(.user, "Hello")]
        }
        let raw: [[String: Any]]?
        if let messages = json["messages"] as? [[String: Any]] {
            raw = messages
        } else if let input = json["input"] as? [[String: Any]] {
            raw = input
        } else {
            raw = nil
        }
        guard let raw else { return [ChatMessage(.user, "Hello")] }
        var out: [ChatMessage] = []
        for item in raw {
            let roleStr = item["role"] as? String ?? "user"
            let content = item["content"] as? String ?? ""
            guard !content.isEmpty else { continue }
            let role: ChatRole = roleStr == "assistant" ? .assistant : (roleStr == "system" ? .system : .user)
            out.append(ChatMessage(role, content))
        }
        return out.isEmpty ? [ChatMessage(.user, "Hello")] : out
    }

    /// Starts the proxy for one active model. A running proxy for
    /// the SAME model is returned as-is (Legacy
    /// `ensureLocalProxyServerStarted`); a running proxy for a
    /// DIFFERENT model is stopped and restarted, so the catalog
    /// and the `streamChat` closure always match the active model.
    ///
    /// Port fallback (Legacy's `NWListener(..., on: .any)` when
    /// 19855 was taken): the requested port is tried first, then
    /// any free loopback port (`LoopbackServer` port 0). Only when
    /// both fail does this throw — never a silent fallback to a
    /// direct model run.
    public func start(active: MuseOtherModelResolution, port: UInt16 = Self.defaultPort, streamChat: @escaping StreamChat) throws -> URL {
        if let existing = lock.withLock({ server }), lock.withLock({ _active }) == active {
            return URL(string: existing.baseURL)!
        }
        stop()
        let server: LoopbackServer
        do {
            server = try LoopbackServer(port: port) { request in
                Self.handle(request: request, active: active, streamChat: streamChat)
            }
        } catch {
            server = try LoopbackServer(port: 0) { request in
                Self.handle(request: request, active: active, streamChat: streamChat)
            }
        }
        lock.withLock {
            self.server = server
            self._active = active
        }
        return URL(string: server.baseURL)!
    }

    public func stop() {
        lock.withLock {
            server?.stop()
            server = nil
            _active = nil
        }
    }

    private static func handle(
        request: LoopbackServer.Request,
        active: MuseOtherModelResolution,
        streamChat: @escaping StreamChat
    ) -> LoopbackServer.Response {
        let path = request.path
        if path.hasPrefix("/muse-code/models") || path == "/models" || path == "/v1/models" {
            return .json(catalogJSON(for: active))
        }
        if path.hasPrefix("/responses") || path.hasPrefix("/v1/responses") || path.hasPrefix("/chat/completions") {
            let messages = parseRequestMessages(request.body)
            let systemPrompt = "You are Assist operating under the Meta Muse SDK bridge with third-party model \(active.displayName)."
            var response = LoopbackServer.Response(
                status: 200,
                contentType: "text/event-stream",
                body: Data(),
                // No `Connection: keep-alive`: LoopbackServer
                // always answers `Connection: close`, and a
                // second Connection header would confuse the
                // host. Streaming still works — the stream
                // closure writes the events, then the connection
                // closes.
                headers: ["Cache-Control": "no-cache"])
            response.stream = { write in
                // The stream runs on the connection's thread: bridge
                // it to structured concurrency with a semaphore.
                let done = DispatchSemaphore(value: 0)
                Task {
                    do {
                        for try await token in streamChat(active.modelID, messages, systemPrompt) {
                            let event = "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\(jsonEscape(token))}\n\n"
                            guard write(Data(event.utf8)) else { break }
                        }
                        let complete = "event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n"
                        _ = write(Data(complete.utf8))
                    } catch {
                        // The client went away or the model failed:
                        // end the stream without fabricating a
                        // completion.
                    }
                    done.signal()
                }
                done.wait()
            }
            return response
        }
        return .text("", status: 404)
    }

    /// JSON-escapes one string as a JSON string literal's inner
    /// content (Legacy `jsonEscape`).
    static func jsonEscape(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "\"\(string)\""
        }
        return String(json.dropFirst().dropLast())
    }
}

// MARK: - Other-models proxy lifecycle (Wave 17, Slice B)
//
// The mode switch Legacy checked at turn time in
// `MetaAssistProvider.executeTurn` — `otherModelsWithMetaSDK ||
// swiftCodeCloudWithMetaSDK` — had no SwiftCode owner: the proxy
// existed, `MetaAssistProvider.proxyBaseURL` was constructor-only,
// and nothing ever started a proxy. This controller is that
// owner. The host (`CodingAssistantModel`) calls it when a Meta
// turn starts: `enable` when other-model mode is on, `disable`
// when it is off or the provider is not Meta.
//
// Honest failures, and deliberately NOT Legacy's fallbacks: a
// missing `muse` binary throws `.museNotFound` (Legacy fell back
// to a direct `executeTurn` through `LLMService`, which has no
// SwiftCode equivalent and whose approval bypass must not be
// recreated); a proxy that cannot bind any port throws
// `.proxyUnavailable`. Neither failure ever silently runs the
// turn on Meta's own models instead.

/// Why the other-models proxy could not start.
public enum MuseOtherModelsProxyError: Error, Sendable, Equatable, LocalizedError {
    /// No `muse` executable was found: other-model mode cannot
    /// run without the Muse host it points at.
    case museNotFound
    /// No loopback port could be bound (the default port is taken
    /// AND no free port could be bound). The string is the
    /// underlying bind error's description.
    case proxyUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .museNotFound:
            return "Other-model mode needs the 'muse' CLI executable, which was not found. Install the Muse Code CLI and sign in once by running `muse` in Terminal."
        case .proxyUnavailable(let detail):
            return "The other-models proxy could not start: \(detail)"
        }
    }
}

/// Owns the other-models proxy's lifetime for the whole process
/// (one proxy, one active model — the same sharing Legacy's
/// `MuseOtherModelsBridge.shared` had). Serialized by actor
/// isolation: concurrent turns cannot race a restart.
///
/// The host owns the mode decision; this controller only owns
/// the server. `enable` is idempotent for the same model
/// (returns the running URL) and restarts for a different one,
/// so `proxyBaseURL` always tracks the running proxy's real URL.
public actor MuseOtherModelsProxyController {
    public static let shared = MuseOtherModelsProxyController()

    private let proxy = MuseLocalProxyServer()

    public init() {}

    /// Whether the proxy is running (other-model mode is on).
    public var isEnabled: Bool { proxy.isRunning }
    /// The running proxy's real URL, or nil when it is stopped.
    /// The host hands this to the provider as `proxyBaseURL`.
    public var proxyBaseURL: String? { proxy.serverURL?.absoluteString }
    /// The model the running proxy serves, or nil when stopped.
    public var activeModel: MuseOtherModelResolution? { proxy.activeModel }

    /// The mode predicate (Legacy `executeTurn`'s
    /// `isOtherActive`): either toggle turns other-model mode on.
    public static func isOtherModelModeEnabled(
        otherModelsWithMetaSDK: Bool,
        swiftCodeCloudWithMetaSDK: Bool
    ) -> Bool {
        otherModelsWithMetaSDK || swiftCodeCloudWithMetaSDK
    }

    /// Starts the proxy for `resolution` (or returns the running
    /// one when it already serves that model). Throws
    /// `.museNotFound` when `executable` is nil and
    /// `.proxyUnavailable` when no port can be bound.
    @discardableResult
    public func enable(
        resolution: MuseOtherModelResolution,
        executable: URL?,
        port: UInt16 = MuseLocalProxyServer.defaultPort,
        streamChat: @escaping MuseLocalProxyServer.StreamChat
    ) throws -> URL {
        guard executable != nil else { throw MuseOtherModelsProxyError.museNotFound }
        do {
            return try proxy.start(active: resolution, port: port, streamChat: streamChat)
        } catch {
            throw MuseOtherModelsProxyError.proxyUnavailable(error.localizedDescription)
        }
    }

    /// Stops the proxy (mode off, or the provider is no longer
    /// Meta). A stopped proxy reports no URL and serves nothing.
    public func disable() {
        proxy.stop()
    }
}
