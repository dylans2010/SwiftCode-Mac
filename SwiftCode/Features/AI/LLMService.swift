import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "LLMService")

public enum LLMProvider: String, CaseIterable, Codable {
    case openRouter = "OpenRouter"
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Gemini"
    case mistral = "Mistral"
    case qwen = "Qwen"
    case offline = "Offline"
    case codex = "Codex"

    public static func from(rawValue: String?) -> LLMProvider {
        guard let rawValue = rawValue else { return .openRouter }
        return LLMProvider(rawValue: rawValue) ?? .openRouter
    }

    public var keychainKey: String {
        switch self {
        case .openRouter: return KeychainService.openRouterAPIKey
        case .anthropic: return "anthropic_api_key"
        case .openai: return "openai_api_key"
        case .google: return "gemini_api_key"
        case .mistral: return "mistral_api_key"
        case .qwen: return "qwen_api_key"
        case .offline: return "offline_model_selected"
        case .codex: return KeychainService.codexUserAPIKey
        }
    }

    public var baseURL: URL {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1")!
        case .openai: return URL(string: "https://api.openai.com/v1")!
        case .google: return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        case .mistral: return URL(string: "https://api.mistral.ai/v1")!
        case .qwen: return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!
        case .offline: return URL(string: "http://localhost")! // Not used for offline
        case .codex: return URL(string: "http://localhost:3003/v1")! // Node bridge port
        }
    }
}

public enum AIRoutingMode: String, CaseIterable {
    case alwaysLocal = "Always Local"
    case alwaysServer = "Always Server"
    case dynamic = "Dynamic"

    public static func from(rawValue: String?) -> AIRoutingMode {
        guard let rawValue else { return .dynamic }
        return AIRoutingMode(rawValue: rawValue) ?? .dynamic
    }
}

public enum LLMError: LocalizedError {
    case invalidKey
    case rateLimited
    case networkError(String)
    case modelNotFound
    case unknown(String)
    case missingOfflineDefaultModel
    case offlineFallbackUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidKey: return "invalid_key"
        case .rateLimited: return "rate_limited"
        case .networkError(let desc): return "network_error: \(desc)"
        case .modelNotFound: return "model_not_found"
        case .unknown(let desc): return desc
        case .missingOfflineDefaultModel: return "No default offline model selected. Download and set a default offline model in Settings."
        case .offlineFallbackUnavailable: return "Server unavailable and no default offline model configured. Add an API key or download an offline model."
        }
    }
}

public struct LLMResponse: Sendable {
    public let modelName: String
    public let completionText: String
    public let tokenUsage: TokenUsage?
    public let latency: TimeInterval

    public struct TokenUsage: Sendable, Codable {
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int

        public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
        }
    }

    public init(modelName: String, completionText: String, tokenUsage: TokenUsage?, latency: TimeInterval) {
        self.modelName = modelName
        self.completionText = completionText
        self.tokenUsage = tokenUsage
        self.latency = latency
    }
}

@MainActor
public final class LLMService: Sendable {
    public static let shared = LLMService()
    private init() {}

    private let aiRoutingModeKey = "ai.routingMode"

    private var urlSession = URLSession(configuration: .default)

    public func recreateSession(for modelID: String) {
        logInfo("[recreateSession] Invalidating current session and creating a fully new URLSession for model: \(modelID)")
        urlSession.invalidateAndCancel()
        urlSession = URLSession(configuration: .default)
        logInfo("[recreateSession] Confirmed: LLMService successfully switched to model: \(modelID)")
    }

    private func logInfo(_ message: String) {
        logger.log("\(message)")
        InternalLoggingManager.shared.log(message, category: .aiProcessing)
    }

    private func logError(_ message: String) {
        logger.error("\(message)")
        InternalLoggingManager.shared.log("[ERROR] \(message)", category: .aiProcessing)
    }

    private func logWarning(_ message: String) {
        logger.warning("\(message)")
        InternalLoggingManager.shared.log("[WARN] \(message)", category: .aiProcessing)
    }

    @MainActor
    public func resolvedRoutingProvider() throws -> LLMProvider {
        let isFMEnabled = FoundationModels.shared.isEnabled
        if isFMEnabled {
            // If Foundation Models is enabled, we bypass others
            return .offline // Or any placeholder since we intercept
        }

        let mode = AIRoutingMode.from(rawValue: UserDefaults.standard.string(forKey: aiRoutingModeKey))
        let preferredProvider = LLMProvider.from(rawValue: UserDefaults.standard.string(forKey: "ai.selectedProvider"))

        logInfo("[resolvedRoutingProvider] Routing Mode: \(mode.rawValue). Preferred Provider: \(preferredProvider.rawValue).")

        switch mode {
        case .alwaysLocal:
            return .offline
        case .alwaysServer:
            if preferredProvider == .codex {
                return .codex
            }
            if hasServerAPIKey(for: preferredProvider) {
                return preferredProvider
            }
            throw LLMError.invalidKey
        case .dynamic:
            if preferredProvider == .codex {
                return .codex
            }
            if hasServerAPIKey(for: preferredProvider) {
                return preferredProvider
            }
            if hasDefaultOfflineModel() {
                return .offline
            }
            throw LLMError.offlineFallbackUnavailable
        }
    }

    private func retrieveAPIKey(for provider: LLMProvider, from keyOverride: String? = nil) -> String {
        if let keyOverride, !keyOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return keyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var key = ""
        if let managerKey = APIKeyManager.shared.retrieveKey(service: apiKeyProvider(for: provider)),
           !managerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            key = managerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if key.isEmpty {
            if let keychainKey = KeychainService.shared.get(forKey: provider.keychainKey),
               !keychainKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                key = keychainKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if key.isEmpty && provider == .openRouter {
            if let hyphenatedKey = KeychainService.shared.get(forKey: "openrouter-api-key"),
               !hyphenatedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                key = hyphenatedKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return key
    }

    private func findCustomEndpoint(for model: String) -> SavedCustomEndpoint? {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomEndpointManager.shared.endpoints.first { endpoint in
            endpoint.models.contains(trimmedModel)
        }
    }

    private func hasServerAPIKey(for provider: LLMProvider) -> Bool {
        guard provider != .offline else { return false }
        if provider == .codex { return true } // Managed by bridge token setup
        let key = retrieveAPIKey(for: provider)
        return !key.isEmpty
    }

    @MainActor
    private func hasDefaultOfflineModel() -> Bool {
        !OfflineModelManager.shared.defaultOfflineModelName.isEmpty && OfflineModelManager.shared.defaultOfflineModelRecord() != nil
    }

    @MainActor
    private func defaultOfflineModelName() throws -> String {
        guard let model = OfflineModelManager.shared.defaultOfflineModelRecord()?.modelName else {
            throw LLMError.missingOfflineDefaultModel
        }
        return model
    }

    @MainActor
    private func defaultOfflineModelDirectory() throws -> URL {
        OfflineModelManager.shared.modelDirectory(for: try defaultOfflineModelName())
    }

    private func apiKeyProvider(for provider: LLMProvider) -> APIKeyProvider {
        switch provider {
        case .openRouter: return .openRouter
        case .anthropic: return .anthropic
        case .openai: return .openai
        case .google: return .google
        case .mistral: return .mistral
        case .qwen: return .qwen
        case .offline: return .openRouter
        case .codex: return .openai
        }
    }

    // MARK: - Core Methods

    @MainActor
    public func generateResponse(prompt: String, useContext: Bool, modelOverride: String? = nil, providerOverride: LLMProvider? = nil) async throws -> String {
        let isFMEnabled = FoundationModels.shared.isEnabled
        logInfo("[generateResponse] Starting response generation. FoundationModels enabled: \(isFMEnabled).")

        if isFMEnabled {
            logInfo("[generateResponse] Foundation Models are enabled. Routing to Apple private on-device reasoning.")
            return try await FoundationModels.shared.generatePrivateResponse(prompt: prompt)
        }

        let provider = try providerOverride ?? resolvedRoutingProvider()
        if provider == .codex {
            logInfo("[generateResponse] Routing response generation to OpenAI Codex.")
            return try await CodexBridgeManager.shared.sendPrompt(prompt)
        }

        if modelOverride == nil && providerOverride == nil && OnDeviceModelRouter.shared.useOnDeviceAI() {
            logInfo("[generateResponse] OnDeviceModelRouter enabled. Routing to on-device AI.")
            return try await OnDeviceModelRouter.shared.generateResponse(prompt: prompt, useContext: useContext)
        }
        return try await generateExternalResponse(prompt: prompt, useContext: useContext, modelOverride: modelOverride, providerOverride: providerOverride)
    }

    @MainActor
    public func generateExternalResponse(prompt: String, useContext: Bool, modelOverride: String? = nil, providerOverride: LLMProvider? = nil) async throws -> String {
        let isFMEnabled = FoundationModels.shared.isEnabled
        logInfo("[generateExternalResponse] Starting external generation. FoundationModels enabled: \(isFMEnabled).")

        if isFMEnabled {
            logInfo("[generateExternalResponse] Foundation Models are enabled. Routing to Apple private on-device reasoning.")
            return try await FoundationModels.shared.generatePrivateResponse(prompt: prompt)
        }

        let provider = try providerOverride ?? resolvedRoutingProvider()
        if provider == .codex {
            logInfo("[generateExternalResponse] Routing external generation to OpenAI Codex.")
            return try await CodexBridgeManager.shared.sendPrompt(prompt)
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "" }

        let antiRepeatInstruction = "Answer the request directly. Do not repeat or restate the user's message unless they explicitly ask for a quote."
        let messageContent: String
        if useContext {
            messageContent = "[Use available project context when relevant.]\n[\(antiRepeatInstruction)]\n\n\(trimmedPrompt)"
        } else {
            messageContent = "[\(antiRepeatInstruction)]\n\n\(trimmedPrompt)"
        }

        let model: String
        if provider == .offline {
            model = try await defaultOfflineModelName()
        } else {
            let selected = modelOverride ?? AppSettings.shared.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
            model = selected.isEmpty ? "openai/gpt-4o-mini" : selected
        }

        logInfo("[generateExternalResponse] Request constructed. Provider: \(provider.rawValue). Model: \(model). Sending chat request.")
        let response = try await sendChatRequest(
            model: model,
            messages: [AIMessage(role: .user, content: messageContent)],
            providerOverride: providerOverride
        )

        logInfo("[generateExternalResponse] Chat request successful. Response completed.")
        return response.completionText
    }

    public func sanitizeResponse(_ response: String, relativeTo prompt: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResponse.isEmpty else { return "" }

        if normalizedForComparison(trimmedResponse) == normalizedForComparison(trimmedPrompt) {
            return ""
        }

        let responseLines = trimmedResponse
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var cleanedLines: [String] = []
        for (index, line) in responseLines.enumerated() {
            if index < 2, !line.isEmpty, normalizedForComparison(line) == normalizedForComparison(trimmedPrompt) {
                continue
            }
            if cleanedLines.last.map(normalizedForComparison) == normalizedForComparison(line) {
                continue
            }
            cleanedLines.append(line)
        }

        let cleaned = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedForComparison(cleaned) == normalizedForComparison(trimmedPrompt) ? "" : cleaned
    }

    private func normalizedForComparison(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    public func validateAPIKey(provider: LLMProvider, key: String) async throws -> Bool {
        logInfo("[validateAPIKey] Validating API key for provider: \(provider.rawValue).")
        if provider == .codex {
            return await CodexBridgeManager.shared.validateAPIKey(key)
        }
        do {
            _ = try await fetchAvailableModels(provider: provider, key: key)
            return true
        } catch {
            logError("[validateAPIKey] Key validation failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func fetchAvailableModels(provider: LLMProvider, key: String) async throws -> [String] {
        if provider == .codex {
            return ["gpt-5-codex", "gpt-4-codex"]
        }
        let url = provider.baseURL.appendingPathComponent("models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupHeaders(for: &request, provider: provider, key: key)

        let (data, response) = try await self.urlSession.data(for: request)
        try handleHTTPError(response, data: data)

        if provider == .anthropic {
            return ["claude-3-5-sonnet-20240620", "claude-3-opus-20240229", "claude-3-haiku-20240307"]
        }

        let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return decoded.data.map { $0.id }
    }

    public func sendChatRequest(model: String, messages: [AIMessage], key: String? = nil, providerOverride: LLMProvider? = nil) async throws -> LLMResponse {
        if let customEndpoint = findCustomEndpoint(for: model) {
            logInfo("[sendChatRequest] Routing to custom endpoint: \(customEndpoint.endpoint) for model: \(model)")
            let startTime = Date()

            var urlString = customEndpoint.isLocal ? "http://localhost:\(customEndpoint.localPort.trimmingCharacters(in: .whitespacesAndNewlines))/v1" : customEndpoint.endpoint
            urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !urlString.lowercased().hasSuffix("/chat/completions") {
                if urlString.hasSuffix("/") {
                    urlString += "chat/completions"
                } else {
                    urlString += "/chat/completions"
                }
            }

            guard let url = URL(string: urlString) else {
                throw NSError(domain: "LLMService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid custom endpoint URL: \(urlString)"])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let apiKey = customEndpoint.isLocal ? "" : customEndpoint.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            for header in customEndpoint.headers {
                let k = header.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let v = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty && !v.isEmpty {
                    request.setValue(v, forHTTPHeaderField: k)
                }
            }

            var apiMessages: [[String: String]] = []
            apiMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            let body: [String: Any] = [
                "model": model,
                "messages": apiMessages,
                "stream": false
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await self.urlSession.data(for: request)
            try handleHTTPError(response, data: data)

            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            let latency = Date().timeIntervalSince(startTime)
            return LLMResponse(
                modelName: decoded.model,
                completionText: decoded.choices.first?.message.content ?? "",
                tokenUsage: decoded.usage.map { LLMResponse.TokenUsage(promptTokens: $0.prompt_tokens, completionTokens: $0.completion_tokens, totalTokens: $0.total_tokens) },
                latency: latency
            )
        }

        let provider: LLMProvider
        if let providerOverride {
            provider = providerOverride
        } else {
            provider = try await resolvedRoutingProvider()
        }

        logInfo("[sendChatRequest] Starting generation request. Provider: \(provider.rawValue). Model: \(model).")

        if provider == .codex {
            logInfo("[sendChatRequest] Delegating request to OpenAI Codex.")
            let prompt = messages.last?.content ?? ""
            let startTime = Date()
            let content = try await CodexBridgeManager.shared.sendPrompt(prompt)
            return LLMResponse(
                modelName: "gpt-5-codex",
                completionText: content,
                tokenUsage: LLMResponse.TokenUsage(promptTokens: 100, completionTokens: 100, totalTokens: 200),
                latency: Date().timeIntervalSince(startTime)
            )
        }

        if provider == .offline {
            return try await runOfflineResponse(messages: messages)
        }

        let actualKey = retrieveAPIKey(for: provider, from: key)
        guard !actualKey.isEmpty else {
            logError("[sendChatRequest] Missing API key for \(provider.rawValue).")
            throw LLMError.invalidKey
        }

        do {
            let startTime = Date()
            let endpoint = provider == .anthropic ? "messages" : "chat/completions"
            let url = provider.baseURL.appendingPathComponent(endpoint)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            setupHeaders(for: &request, provider: provider, key: actualKey)

            let body = try buildRequestBody(provider: provider, model: model, messages: messages, stream: false)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            logInfo("[sendChatRequest] Sending non-streaming API request to \(provider.rawValue)...")
            let (data, response) = try await self.urlSession.data(for: request)
            try handleHTTPError(response, data: data)

            let latency = Date().timeIntervalSince(startTime)
            logInfo("[sendChatRequest] Request finished in \(latency) seconds.")

            if provider == .anthropic {
                let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
                return LLMResponse(
                    modelName: decoded.model,
                    completionText: decoded.content.first?.text ?? "",
                    tokenUsage: LLMResponse.TokenUsage(
                        promptTokens: decoded.usage.input_tokens,
                        completionTokens: decoded.usage.output_tokens,
                        totalTokens: decoded.usage.input_tokens + decoded.usage.output_tokens
                    ),
                    latency: latency
                )
            } else {
                let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                return LLMResponse(
                    modelName: decoded.model,
                    completionText: decoded.choices.first?.message.content ?? "",
                    tokenUsage: decoded.usage.map { LLMResponse.TokenUsage(promptTokens: $0.prompt_tokens, completionTokens: $0.completion_tokens, totalTokens: $0.total_tokens) },
                    latency: latency
                )
            }
        } catch {
            logWarning("[sendChatRequest] Request failed: \(error.localizedDescription). Checking fallback eligibility.")
            if await shouldFallbackToOffline(for: provider) {
                logInfo("[sendChatRequest] Falling back to offline runner.")
                return try await runOfflineResponse(messages: messages)
            }
            throw error
        }
    }

    public func measureLatency(provider: LLMProvider, key: String) async throws -> TimeInterval {
        let startTime = Date()
        _ = try await fetchAvailableModels(provider: provider, key: key)
        return Date().timeIntervalSince(startTime)
    }

    public func streamChat(
        messages: [AIMessage],
        model: String,
        systemPrompt: String,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
        if let customEndpoint = findCustomEndpoint(for: model) {
            logInfo("[streamChat] Routing stream to custom endpoint: \(customEndpoint.endpoint) for model: \(model)")

            var urlString = customEndpoint.isLocal ? "http://localhost:\(customEndpoint.localPort.trimmingCharacters(in: .whitespacesAndNewlines))/v1" : customEndpoint.endpoint
            urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !urlString.lowercased().hasSuffix("/chat/completions") {
                if urlString.hasSuffix("/") {
                    urlString += "chat/completions"
                } else {
                    urlString += "/chat/completions"
                }
            }

            guard let url = URL(string: urlString) else {
                throw NSError(domain: "LLMService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid custom endpoint URL"])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let apiKey = customEndpoint.isLocal ? "" : customEndpoint.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            for header in customEndpoint.headers {
                let k = header.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let v = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty && !v.isEmpty {
                    request.setValue(v, forHTTPHeaderField: k)
                }
            }

            var apiMessages: [[String: String]] = []
            if !systemPrompt.isEmpty {
                apiMessages.append(["role": "system", "content": systemPrompt])
            }
            apiMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            let body: [String: Any] = [
                "model": model,
                "messages": apiMessages,
                "stream": true
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (stream, response) = try await self.urlSession.bytes(for: request)
            try handleHTTPError(response, data: nil)

            for try await line in stream.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                guard jsonString != "[DONE]" else { break }

                if let data = jsonString.data(using: .utf8) {
                    if let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
                       let token = chunk.choices.first?.delta.content {
                        await onToken(token)
                    }
                }
            }
            return
        }

        let isFMEnabled = await FoundationModels.shared.isEnabled
        logInfo("[streamChat] Starting stream request. FoundationModels enabled: \(isFMEnabled).")

        if isFMEnabled {
            logInfo("[streamChat] Foundation Models are enabled. Routing to Apple private on-device reasoning.")
            try await FoundationModels.shared.streamPrivateResponse(prompt: messages.last?.content ?? "", onToken: onToken)
            return
        }

        let provider = try await resolvedRoutingProvider()

        if provider == .codex {
            logInfo("[streamChat] Routing stream to OpenAI Codex bridge.")
            try await CodexBridgeManager.shared.streamPrompt(messages.last?.content ?? "", onToken: onToken)
            return
        }

        if provider == .offline {
            logInfo("[streamChat] Routing stream to offline model.")
            _ = try await defaultOfflineModelName()
            try await OfflineModelRunner.shared.loadModel(at: try await defaultOfflineModelDirectory())
            try await OfflineModelRunner.shared.streamResponse(prompt: messages.last?.content ?? "") { token in
                Task {
                    await onToken(token)
                }
            }
            return
        }

        do {
            if provider == .openRouter {
                logInfo("[streamChat] Streaming with OpenRouter via direct connection.")
                try await OpenRouterService.shared.streamChatDirect(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt,
                    onToken: onToken
                )
                return
            }

            let key = retrieveAPIKey(for: provider)
            guard !key.isEmpty else {
                logError("[streamChat] Missing API key for stream.")
                throw LLMError.invalidKey
            }

            let endpoint = provider == .anthropic ? "messages" : "chat/completions"
            let url = provider.baseURL.appendingPathComponent(endpoint)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            setupHeaders(for: &request, provider: provider, key: key)

            let body = try buildRequestBody(provider: provider, model: model, messages: messages, systemPrompt: systemPrompt, stream: true)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            logInfo("[streamChat] Connecting to stream at \(provider.rawValue)...")
            let (stream, response) = try await self.urlSession.bytes(for: request)
            try handleHTTPError(response, data: nil)

            logInfo("[streamChat] Stream connected. Consuming lines.")
            for try await line in stream.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                guard jsonString != "[DONE]" else { break }

                if let data = jsonString.data(using: .utf8) {
                    if provider == .anthropic {
                        if let chunk = try? JSONDecoder().decode(AnthropicStreamChunk.self, from: data),
                           let token = chunk.delta?.text {
                            await onToken(token)
                        }
                    } else {
                        if let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
                           let token = chunk.choices.first?.delta.content {
                            await onToken(token)
                        }
                    }
                }
            }
        } catch {
            logWarning("[streamChat] Stream failed: \(error.localizedDescription). Checking fallback eligibility.")
            if await shouldFallbackToOffline(for: provider) {
                logInfo("[streamChat] Falling back to offline runner stream.")
                _ = try await defaultOfflineModelName()
                try await OfflineModelRunner.shared.loadModel(at: try await defaultOfflineModelDirectory())
                try await OfflineModelRunner.shared.streamResponse(prompt: messages.last?.content ?? "") { token in
                    Task { await onToken(token) }
                }
                return
            }
            throw error
        }
    }

    @MainActor
    public func streamChatCompletion(request: AIAssistantRequest) async throws -> AsyncThrowingStream<String, Error> {
        let isFMEnabled = FoundationModels.shared.isEnabled
        logInfo("[streamChatCompletion] FoundationModels enabled: \(isFMEnabled).")

        if isFMEnabled {
            logInfo("[streamChatCompletion] Streaming via Apple Foundation Models.")
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let prompt = request.messages.last?.content ?? ""
                        try await FoundationModels.shared.streamPrivateResponse(prompt: prompt) { token in
                            continuation.yield(token)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        let provider = try await resolvedRoutingProvider()
        if provider == .codex {
            logInfo("[streamChatCompletion] Streaming via OpenAI Codex bridge.")
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let prompt = request.messages.last?.content ?? ""
                        try await CodexBridgeManager.shared.streamPrompt(prompt) { token in
                            continuation.yield(token)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        if provider == .offline {
            logInfo("[streamChatCompletion] Streaming via offline model.")
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let prompt = request.messages.last?.content ?? ""
                        _ = try await defaultOfflineModelName()
                        try await OfflineModelRunner.shared.loadModel(at: try await defaultOfflineModelDirectory())
                        try await OfflineModelRunner.shared.streamResponse(prompt: prompt) { token in
                            continuation.yield(token)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        // Default: OpenRouter / standard streaming
        logInfo("[streamChatCompletion] Streaming via default provider \(provider.rawValue).")
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.streamChat(
                        messages: request.messages,
                        model: request.model,
                        systemPrompt: "You are a professional assistant.",
                        onToken: { token in
                            continuation.yield(token)
                        }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    @MainActor
    private func shouldFallbackToOffline(for provider: LLMProvider) -> Bool {
        let mode = AIRoutingMode.from(rawValue: UserDefaults.standard.string(forKey: aiRoutingModeKey))
        return mode == .dynamic && provider != .offline && hasDefaultOfflineModel()
    }

    private func runOfflineResponse(messages: [AIMessage]) async throws -> LLMResponse {
        let startTime = Date()
        let offlineModel = try await defaultOfflineModelName()
        try await OfflineModelRunner.shared.loadModel(at: try await defaultOfflineModelDirectory())
        let completionText = try await OfflineModelRunner.shared.generateResponse(prompt: messages.last?.content ?? "")
        return LLMResponse(modelName: offlineModel, completionText: completionText, tokenUsage: nil, latency: Date().timeIntervalSince(startTime))
    }

    // MARK: - Helpers

    private func setupHeaders(for request: inout URLRequest, provider: LLMProvider, key: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch provider {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .google:
            request.url = request.url?.appending(queryItems: [URLQueryItem(name: "key", value: key)])
        default:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    private func buildRequestBody(provider: LLMProvider, model: String, messages: [AIMessage], systemPrompt: String = "", stream: Bool) throws -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "stream": stream
        ]

        if provider == .anthropic {
            if !systemPrompt.isEmpty {
                body["system"] = systemPrompt
            }
            body["messages"] = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            body["max_tokens"] = 4096
        } else {
            var apiMessages: [[String: String]] = []
            if !systemPrompt.isEmpty {
                apiMessages.append(["role": "system", "content": systemPrompt])
            }
            apiMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            body["messages"] = apiMessages
        }

        return body
    }

    private func handleHTTPError(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        if httpResponse.statusCode == 200 { return }

        let errorDesc = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
        logError("[Third-Party API Error] Status: \(httpResponse.statusCode). Response Payload: \(errorDesc)")

        switch httpResponse.statusCode {
        case 401: throw LLMError.invalidKey
        case 429: throw LLMError.rateLimited
        case 404: throw LLMError.modelNotFound
        default:
            throw LLMError.networkError(errorDesc)
        }
    }
}

// MARK: - Decodable Structures

private struct ModelListResponse: Decodable {
    struct ModelData: Decodable {
        let id: String
    }
    let data: [ModelData]
}

private struct ChatCompletionResponse: Decodable {
    let model: String
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
    struct Usage: Decodable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
    let usage: Usage?
}

private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}

private struct AnthropicResponse: Decodable {
    let model: String
    struct Content: Decodable {
        let text: String
    }
    let content: [Content]
    struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
    }
    let usage: Usage
}

private struct AnthropicStreamChunk: Decodable {
    struct Delta: Decodable {
        let text: String?
    }
    let delta: Delta?
}
