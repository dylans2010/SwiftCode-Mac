import Foundation

public struct AIConversation: Identifiable, Sendable, Codable {
    public let id: UUID
    public var messages: [AIMessage]
    public var lastUpdated: Date

    public init(messages: [AIMessage] = []) {
        self.id = UUID()
        self.messages = messages
        self.lastUpdated = Date()
    }
}
