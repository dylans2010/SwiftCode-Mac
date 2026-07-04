import Foundation

public protocol AIProvider: Sendable {
    func streamAgentTurn(model: String, messages: [AgentMessage], tools: [[String: Any]]?) async throws -> AsyncThrowingStream<AgentStreamEvent, Error>
}

public enum AIProviderCapability: String, Codable, Sendable {
    case toolCalling = "tool_calling"
    case vision = "vision"
    case streaming = "streaming"
}
