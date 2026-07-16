import Foundation
import Observation

@Observable
@MainActor
public final class AgentSession: Identifiable, @MainActor Decodable, @MainActor Encodable, @unchecked Sendable {
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

    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, messages, checklist, turnState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.messages = try container.decode([AgentMessage].self, forKey: .messages)
        self.checklist = try container.decode(AgentChecklistState.self, forKey: .checklist)
        self.turnState = try container.decode(AgentTurnState.self, forKey: .turnState)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(messages, forKey: .messages)
        try container.encode(checklist, forKey: .checklist)
        try container.encode(turnState, forKey: .turnState)
    }
}
