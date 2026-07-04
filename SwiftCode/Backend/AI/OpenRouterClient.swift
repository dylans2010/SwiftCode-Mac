import Foundation

public actor OpenRouterClient {
    public static let shared = OpenRouterClient()

    public func fetchModels() async throws -> [OpenRouterModel] {
        let apiKey = try await KeychainService.shared.get(account: "openrouter-api-key") ?? ""
        // SAFETY: The URL is a valid constant string.
        var urlRequest = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppError.aiError("Failed to fetch models from OpenRouter")
        }

        struct ModelsResponse: Codable {
            let data: [OpenRouterModel]
        }

        let decodedResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decodedResponse.data
    }

    public func streamChatCompletion(request: AIAssistantRequest) async throws -> AsyncThrowingStream<String, Error> {
        let apiKey = try await KeychainService.shared.get(account: "openrouter-api-key") ?? ""
        // SAFETY: The URL is a valid constant string.
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

    public func streamAgentTurn(model: String, messages: [AgentMessage], tools: [[String: Any]]?) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let apiKey = try await KeychainService.shared.get(account: "openrouter-api-key") ?? ""
        // SAFETY: The URL is a valid constant string.
        var urlRequest = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OpenRouterRequestBuilder.shared.buildAgentRequest(model: model, messages: messages, tools: tools)
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
                            if let event = decodeAgentEvent(dataStr) {
                                continuation.yield(event)
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

    private func decodeAgentEvent(_ jsonString: String) -> AgentStreamEvent? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else {
            return nil
        }

        if let content = delta["content"] as? String {
            return .text(content)
        }

        if let toolCallsDicts = delta["tool_calls"] as? [[String: Any]] {
            let toolCalls = toolCallsDicts.compactMap { dict -> AgentToolCall? in
                guard let id = dict["id"] as? String,
                      let function = dict["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let arguments = function["arguments"] as? String else {
                    return nil
                }
                return AgentToolCall(id: id, name: name, arguments: arguments)
            }
            return .toolCall(toolCalls)
        }

        return nil
    }
}

public enum AgentStreamEvent: Sendable {
    case text(String)
    case toolCall([AgentToolCall])
}

public struct AIAssistantRequest: Sendable {
    public let model: String
    public let messages: [AIMessage]
}
