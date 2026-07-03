import Foundation

public actor OpenRouterClient {
    public static let shared = OpenRouterClient()

    public func streamChatCompletion(request: AIAssistantRequest) async throws -> AsyncThrowingStream<String, Error> {
        let apiKey = try await KeychainService.shared.get(account: "openrouter-api-key") ?? ""
        var urlRequest = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": request.model,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": true
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (result, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppError.aiError("Failed to connect to OpenRouter")
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in result.lines {
                        if line.hasPrefix("data: ") {
                            let dataStr = String(line.dropFirst(6))
                            if dataStr == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            if let chunk = SSEStreamDecoder.shared.decode(dataStr) {
                                continuation.yield(chunk)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public struct AIAssistantRequest: Sendable {
    public let model: String
    public let messages: [AIMessage]
}
