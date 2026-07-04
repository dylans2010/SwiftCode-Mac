import Foundation

public struct OpenRouterAIProvider: AIProvider {
    public static let shared = OpenRouterAIProvider()

    public func streamAgentTurn(model: String, messages: [AgentMessage], tools: [[String: Any]]?) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        return try await OpenRouterClient.shared.streamAgentTurn(model: model, messages: messages, tools: tools)
    }
}
