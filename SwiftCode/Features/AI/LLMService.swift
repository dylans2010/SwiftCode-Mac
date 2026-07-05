import Foundation

enum LLMProvider: String, CaseIterable {
    case openRouter = "OpenRouter"
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Gemini"
    case mistral = "Mistral"
    case qwen = "Qwen"
    case offline = "Offline"

    static func from(rawValue: String?) -> LLMProvider {
        guard let rawValue = rawValue else { return .openRouter }
        return LLMProvider(rawValue: rawValue) ?? .openRouter
    }

    var keychainKey: String {
        switch self {
        case .openRouter: return KeychainService.openRouterAPIKey
        case .anthropic: return "anthropic_api_key"
        case .openai: return "openai_api_key"
        case .google: return "gemini_api_key"
        case .mistral: return "mistral_api_key"
        case .qwen: return "qwen_api_key"
        case .offline: return "offline_model_selected"
        }
    }

    var baseURL: URL {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1")!
        case .openai: return URL(string: "https://api.openai.com/v1")!
        case .google: return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        case .mistral: return URL(string: "https://api.mistral.ai/v1")!
        case .qwen: return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!
        case .offline: return URL(string: "http://localhost")! // Not used for offline
        }
    }
}



enum AIRoutingMode: String, CaseIterable {
    case alwaysLocal = "Always Local"
    case alwaysServer = "Always Server"
    case dynamic = "Dynamic"

    static func from(rawValue: String?) -> AIRoutingMode {
        guard let rawValue else { return .dynamic }
        return AIRoutingMode(rawValue: rawValue) ?? .dynamic
    }
}

enum LLMError: LocalizedError {
    case invalidKey
    case rateLimited
    case networkError(String)
    case modelNotFound
    case unknown(String)
    case missingOfflineDefaultModel
    case offlineFallbackUnavailable

    var errorDescription: String? {
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

struct LLMResponse {
    let modelName: String
    let completionText: String
    let tokenUsage: TokenUsage?
    let latency: TimeInterval

    struct TokenUsage {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
    }
}

final class LLMService {
    static let shared = LLMService()
    private init() {}

    private let aiRoutingModeKey = "ai.routingMode"

    @MainActor
    private func resolvedRoutingProvider() throws -> LLMProvider {
        let mode = AIRoutingMode.from(rawValue: UserDefaults.standard.string(forKey: aiRoutingModeKey))
        let preferredProvider = LLMProvider.from(rawValue: UserDefaults.standard.string(forKey: "ai.selectedProvider"))

        switch mode {
        case .alwaysLocal:
            return .offline
        case .alwaysServer:
            if hasServerAPIKey(for: preferredProvider) {
                return preferredProvider
            }
            throw LLMError.invalidKey
        case .dynamic:
            if hasServerAPIKey(for: preferredProvider) {
                return preferredProvider
            }
            if hasDefaultOfflineModel() {
                return .offline
            }
            throw LLMError.offlineFallbackUnavailable
        }
    }

    private func hasServerAPIKey(for provider: LLMProvider) -> Bool {
        guard provider != .offline else { return false }
        let key = APIKeyManager.shared.retrieveKey(service: apiKeyProvider(for: provider))
            ?? KeychainService.shared.get(forKey: provider.keychainKey)
            ?? ""
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
        }
    }

    // MARK: - Core Methods

    @MainActor
    func generateResponse(prompt: String, useContext: Bool, modelOverride: String? = nil, providerOverride: LLMProvider? = nil) async throws -> String {
        if modelOverride == nil && providerOverride == nil && OnDeviceModelRouter.shared.useOnDeviceAI() {
            return try await OnDeviceModelRouter.shared.generateResponse(prompt: prompt, useContext: useContext)
        }
        return try await generateExternalResponse(prompt: prompt, useContext: useContext, modelOverride: modelOverride, providerOverride: providerOverride)
    }

    @MainActor
    func generateExternalResponse(prompt: String, useContext: Bool, modelOverride: String? = nil, providerOverride: LLMProvider? = nil) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "" }

        let antiRepeatInstruction = "Answer the request directly. Do not repeat or restate the user's message unless they explicitly ask for a quote."
        let messageContent: String
        if useContext {
            messageContent = "[Use available project context when relevant.]\n[\(antiRepeatInstruction)]\n\n\(trimmedPrompt)"
        } else {
            messageContent = "[\(antiRepeatInstruction)]\n\n\(trimmedPrompt)"
        }

        let provider = try providerOverride ?? resolvedRoutingProvider()
        let model: String
        if provider == .offline {
            model = try await defaultOfflineModelName()
        } else {
            let selected = modelOverride ?? AppSettings.shared.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
            model = selected.isEmpty ? "openai/gpt-4o-mini" : selected
        }

        let response = try await sendChatRequest(
            model: model,
            messages: [AIMessage(role: "user", content: messageContent)],
            providerOverride: providerOverride
        )

        return response.completionText
    }


    func sanitizeResponse(_ response: String, relativeTo prompt: String) -> String {
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


    func validateAPIKey(provider: LLMProvider, key: String) async throws -> Bool {
        do {
            // For most providers, fetching models is a good way to validate
            _ = try await fetchAvailableModels(provider: provider, key: key)
            return true
        } catch {
            throw error
        }
    }

    func fetchAvailableModels(provider: LLMProvider, key: String) async throws -> [String] {
        let url = provider.baseURL.appendingPathComponent("models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupHeaders(for: &request, provider: provider, key: key)

        let (data, response) = try await URLSession.shared.data(for: request)
        try handleHTTPError(response, data: data)

        // Anthropic doesn't have a standard /models endpoint like OpenAI
        if provider == .anthropic {
            return ["claude-3-5-sonnet-20240620", "claude-3-opus-20240229", "claude-3-haiku-20240307"]
        }

        let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return decoded.data.map { $0.id }
    }

    func sendChatRequest(model: String, messages: [AIMessage], key: String? = nil, providerOverride: LLMProvider? = nil) async throws -> LLMResponse {
        let provider: LLMProvider
        if let providerOverride {
            provider = providerOverride
        } else {
            provider = try await resolvedRoutingProvider()
        }

        if provider == .offline {
            return try await runOfflineResponse(messages: messages)
        }

        let actualKey = key ?? APIKeyManager.shared.retrieveKey(service: apiKeyProvider(for: provider)) ?? KeychainService.shared.get(forKey: provider.keychainKey) ?? ""
        guard !actualKey.isEmpty else { throw LLMError.invalidKey }

        do {
            let startTime = Date()
            let endpoint = provider == .anthropic ? "messages" : "chat/completions"
            let url = provider.baseURL.appendingPathComponent(endpoint)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            setupHeaders(for: &request, provider: provider, key: actualKey)

            let body = try buildRequestBody(provider: provider, model: model, messages: messages, stream: false)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            try handleHTTPError(response, data: data)

            let latency = Date().timeIntervalSince(startTime)

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
            if await shouldFallbackToOffline(for: provider) {
                return try await runOfflineResponse(messages: messages)
            }
            throw error
        }
    }

    func measureLatency(provider: LLMProvider, key: String) async throws -> TimeInterval {
        let startTime = Date()
        // Simple validation or model fetch to measure latency
        _ = try await fetchAvailableModels(provider: provider, key: key)
        return Date().timeIntervalSince(startTime)
    }

    func streamChat(
        messages: [AIMessage],
        model: String,
        systemPrompt: String,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
        let provider = try await resolvedRoutingProvider()

        if provider == .offline {
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
                try await OpenRouterService.shared.streamChat(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt,
                    onToken: onToken
                )
                return
            }

            let key = APIKeyManager.shared.retrieveKey(service: apiKeyProvider(for: provider)) ?? KeychainService.shared.get(forKey: provider.keychainKey) ?? ""
            guard !key.isEmpty else { throw LLMError.invalidKey }

            let endpoint = provider == .anthropic ? "messages" : "chat/completions"
            let url = provider.baseURL.appendingPathComponent(endpoint)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            setupHeaders(for: &request, provider: provider, key: key)

            let body = try buildRequestBody(provider: provider, model: model, messages: messages, systemPrompt: systemPrompt, stream: true)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (stream, response) = try await URLSession.shared.bytes(for: request)
            try handleHTTPError(response, data: nil)

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
            if await shouldFallbackToOffline(for: provider) {
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
            body["messages"] = messages.map { ["role": $0.role, "content": $0.content] }
            body["max_tokens"] = 4096
        } else {
            var apiMessages: [[String: String]] = []
            if !systemPrompt.isEmpty {
                apiMessages.append(["role": "system", "content": systemPrompt])
            }
            apiMessages += messages.map { ["role": $0.role, "content": $0.content] }
            body["messages"] = apiMessages
        }

        return body
    }

    private func handleHTTPError(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        if httpResponse.statusCode == 200 { return }

        switch httpResponse.statusCode {
        case 401: throw LLMError.invalidKey
        case 429: throw LLMError.rateLimited
        case 404: throw LLMError.modelNotFound
        default:
            let errorDesc = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
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
