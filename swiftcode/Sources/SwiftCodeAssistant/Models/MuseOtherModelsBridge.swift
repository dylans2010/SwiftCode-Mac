import Foundation
import Network
import os

public struct MuseOtherModel: Sendable, Equatable {
    public let id: String
    public let displayName: String
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

    public static func resolveActiveModel(
        selectedOtherModelID: String,
        selectedOtherModelProvider: String = "",
        generalModelID: String = "",
        discovered: [AssistCandidateModel] = [],
        customEndpoints: [MuseCustomEndpoint] = [],
        cloudModelIDs: [String] = [],
        onlyUseFree: Bool = false
    ) -> MuseOtherModelResolution {
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

        if let firstEndpoint = customEndpoints.first {
            let eligible = AssistModelEligibilityPolicy.filterEligibleModelIDs(firstEndpoint.models, onlyUseFreeModels: onlyUseFree)
            if let firstModel = eligible.first {
                return MuseOtherModelResolution(modelID: firstModel, displayName: "\(firstEndpoint.name): \(firstModel)", provider: "Custom Model Setup")
            }
        }

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

        let available = availableOtherModels(
            discovered: discovered, customEndpoints: customEndpoints,
            cloudModelIDs: cloudModelIDs, onlyUseFree: onlyUseFree)
        if let best = available.first(where: { $0.supportsAgenticUse && $0.supportsToolCalling }) ?? available.first {
            return MuseOtherModelResolution(modelID: best.modelIdentifier, displayName: best.displayName, provider: best.providerName)
        }

        return onlyUseFree
            ? MuseOtherModelResolution(modelID: "openrouter/free", displayName: "OpenRouter Free", provider: "OpenRouter")
            : MuseOtherModelResolution(modelID: "gpt-4o", displayName: "OpenAI GPT-4o", provider: "OpenAI")
    }
}

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

public struct MuseParsedToolCall: Sendable, Equatable {
    public let toolName: String
    public let argumentsJSON: String
    public init(toolName: String, argumentsJSON: String) {
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }
}

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

public final class MuseLocalProxyServer: @unchecked Sendable {
    public typealias StreamChat = @Sendable (String, [ChatMessage], String) -> AsyncThrowingStream<String, Error>

    public static let defaultPort: UInt16 = 19855

    private let lock = NSLock()
    private var server: LoopbackServer?
    private var _active: MuseOtherModelResolution?

    public init() {}

    public var isRunning: Bool { lock.withLock { server != nil } }
    public var serverURL: URL? { lock.withLock { server.map { URL(string: $0.baseURL)! } } }
    public var activeModel: MuseOtherModelResolution? { lock.withLock { _active } }

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

    public func start(active: MuseOtherModelResolution, port: UInt16 = MuseLocalProxyServer.defaultPort, streamChat: @escaping StreamChat) throws -> URL {
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
                headers: ["Cache-Control": "no-cache"])
            response.stream = { write in
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
                    }
                    done.signal()
                }
                done.wait()
            }
            return response
        }
        return .text("", status: 404)
    }

    static func jsonEscape(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "\"\(string)\""
        }
        return String(json.dropFirst().dropLast())
    }
}

public enum MuseOtherModelsProxyError: Error, Sendable, Equatable, LocalizedError {
    case museNotFound
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

public actor MuseOtherModelsProxyController {
    public static let shared = MuseOtherModelsProxyController()

    private let proxy = MuseLocalProxyServer()

    public init() {}

    public var isEnabled: Bool { proxy.isRunning }
    public var proxyBaseURL: String? { proxy.serverURL?.absoluteString }
    public var activeModel: MuseOtherModelResolution? { proxy.activeModel }

    public static func isOtherModelModeEnabled(
        otherModelsWithMetaSDK: Bool,
        swiftCodeCloudWithMetaSDK: Bool
    ) -> Bool {
        otherModelsWithMetaSDK || swiftCodeCloudWithMetaSDK
    }

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

    public func disable() {
        proxy.stop()
    }
}

private final class GenerationState: @unchecked Sendable {
    private let lock = NSLock()
    private var _fullGeneratedText = ""
    private var _isInThinkingBlock = false
    private var _currentThinking = ""
    private var _isCancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _isCancelled = true
    }

    func appendText(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        _fullGeneratedText += text
    }

    var fullGeneratedText: String {
        lock.lock(); defer { lock.unlock() }
        return _fullGeneratedText
    }

    func processToken(
        _ token: String,
        onThinkingDelta: ((String) -> Void)?,
        onTextDelta: (String) -> Void
    ) {
        lock.lock(); defer { lock.unlock() }
        guard !_isCancelled else { return }

        _fullGeneratedText += token

        if token.contains("<think>") {
            _isInThinkingBlock = true
            let cleaned = token.replacingOccurrences(of: "<think>", with: "")
            if !cleaned.isEmpty {
                _currentThinking += cleaned
                onThinkingDelta?(cleaned)
            }
            return
        } else if token.contains("</think>") {
            _isInThinkingBlock = false
            let parts = token.components(separatedBy: "</think>")
            if let thoughtPart = parts.first, !thoughtPart.isEmpty {
                _currentThinking += thoughtPart
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

        if _isInThinkingBlock {
            _currentThinking += token
            onThinkingDelta?(token)
        } else {
            onTextDelta(token)
        }
    }
}
