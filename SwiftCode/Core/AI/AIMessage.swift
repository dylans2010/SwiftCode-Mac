import Foundation

public struct AIMessage: Identifiable, Sendable, Codable {
    public let id: UUID
    public let role: Role
    public var content: String
    public let modelUsed: String?
    public let timestamp: Date

    public enum Role: String, Sendable, Codable {
        case user
        case assistant
        case system
    }

    public init(role: Role, content: String, modelUsed: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.modelUsed = modelUsed
        self.timestamp = Date()
    }
}
