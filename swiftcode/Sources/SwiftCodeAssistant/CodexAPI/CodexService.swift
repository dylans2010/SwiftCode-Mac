import Foundation

public struct CodexLLMResponse: Sendable {
    public struct TokenUsage: Sendable {
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int

        public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
        }
    }

    public let modelName: String
    public let completionText: String
    public let tokenUsage: TokenUsage?
    public let latency: TimeInterval

    public init(modelName: String, completionText: String, tokenUsage: TokenUsage?, latency: TimeInterval) {
        self.modelName = modelName
        self.completionText = completionText
        self.tokenUsage = tokenUsage
        self.latency = latency
    }
}

public final class CodexService: Sendable {
    private let session: URLSession
    private let requestBuilder = CodexRequestBuilder()
    private let responseParser = CodexResponseParser()
    private let maxAttempts = 3
    private let requestTimeout: TimeInterval = 60

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(prompt: String, session codexSession: CodexSession, apiKey: String, model: String, taskType: CodexTaskType) async throws -> CodexLLMResponse {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                var request = try requestBuilder.makeRequest(model: model, prompt: prompt, session: codexSession, taskType: taskType, stream: false)
                request.timeoutInterval = requestTimeout
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                let startTime = Date()
                let (data, response) = try await session.data(for: request)
                var parsed = try responseParser.parseResponse(data: data, response: response)
                parsed = CodexLLMResponse(modelName: parsed.modelName, completionText: parsed.completionText, tokenUsage: parsed.tokenUsage, latency: Date().timeIntervalSince(startTime))
                return parsed
            } catch {
                lastError = error
                if Task.isCancelled { throw CancellationError() }
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                    continue
                }
            }
        }

        throw lastError ?? CodexAPIError.unknown("Codex request failed.")
    }

    public func validateAPIKey(_ apiKey: String, model: String) async -> Bool {
        let validationSession = CodexSession(messages: [])
        do {
            _ = try await send(prompt: "Respond with the single word VALID.", session: validationSession, apiKey: apiKey, model: model, taskType: .general)
            return true
        } catch {
            return false
        }
    }
}
