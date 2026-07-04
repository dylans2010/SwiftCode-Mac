import Foundation

public struct AgentMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public let role: AIMessage.Role
    public var content: [AgentMessageContent]
    public let timestamp: Date

    public init(id: UUID = UUID(), role: AIMessage.Role, content: [AgentMessageContent], timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
