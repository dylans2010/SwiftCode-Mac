import Foundation

public struct AgentSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public var messages: [AgentMessage]
    public var checklist: AgentChecklistState
    public var turnState: AgentTurnState

    public init(id: UUID = UUID(), messages: [AgentMessage] = [], checklist: AgentChecklistState = .init(tasks: []), turnState: AgentTurnState = .idle) {
        self.id = id
        self.messages = messages
        self.checklist = checklist
        self.turnState = turnState
    }
}
