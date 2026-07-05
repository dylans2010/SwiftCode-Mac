import Foundation

final class CodexService {
    private let session: URLSession
    private let requestBuilder = CodexRequestBuilder()
    private let responseParser = CodexResponseParser()
    private let maxAttempts = 3
    private let requestTimeout: TimeInterval = 60

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(prompt: String, session codexSession: CodexSession, apiKey: String, model: String, taskType: CodexTaskType) async throws -> LLMResponse {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                var request = try requestBuilder.makeRequest(model: model, prompt: prompt, session: codexSession, taskType: taskType, stream: false)
                request.timeoutInterval = requestTimeout
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                let startTime = Date()
                let (data, response) = try await session.data(for: request)
                var parsed = try responseParser.parseResponse(data: data, response: response)
                parsed = LLMResponse(modelName: parsed.modelName, completionText: parsed.completionText, tokenUsage: parsed.tokenUsage, latency: Date().timeIntervalSince(startTime))
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

        throw lastError ?? LLMError.unknown("Codex request failed.")
    }

    func validateAPIKey(_ apiKey: String, model: String) async -> Bool {
        let validationSession = CodexSession(messages: [])
        do {
            _ = try await send(prompt: "Respond with the single word VALID.", session: validationSession, apiKey: apiKey, model: model, taskType: .general)
            return true
        } catch {
            return false
        }
    }
}
