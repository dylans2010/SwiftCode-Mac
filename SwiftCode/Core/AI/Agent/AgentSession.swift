import Foundation
import Observation

public enum AgentChatMode: String, Codable, Sendable, CaseIterable {
    case chat = "Chat"
    case agent = "Agent"
}

@Observable
@MainActor
public final class AgentSession: Identifiable, @MainActor Codable, Sendable {
    public let id: UUID
    public var messages: [AgentMessage]
    public var checklist: AgentChecklistState
    public var turnState: AgentTurnState
    public var mode: AgentChatMode
    public var title: String?
    public var isPinned: Bool
    public var lastModified: Date

    public init(
        id: UUID = UUID(),
        messages: [AgentMessage] = [],
        checklist: AgentChecklistState = .init(tasks: []),
        turnState: AgentTurnState = .idle,
        mode: AgentChatMode = .chat,
        title: String? = nil,
        isPinned: Bool = false,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.messages = messages
        self.checklist = checklist
        self.turnState = turnState
        self.mode = mode
        self.title = title
        self.isPinned = isPinned
        self.lastModified = lastModified
    }

    // Codable conformance for @MainActor class
    enum CodingKeys: String, CodingKey {
        case id, messages, checklist, turnState, mode, title, isPinned, lastModified
    }

    @MainActor
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.messages = try container.decode([AgentMessage].self, forKey: .messages)
        self.checklist = try container.decode(AgentChecklistState.self, forKey: .checklist)
        self.turnState = try container.decode(AgentTurnState.self, forKey: .turnState)
        self.mode = try container.decodeIfPresent(AgentChatMode.self, forKey: .mode) ?? .chat
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
    }

    @MainActor
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(messages, forKey: .messages)
        try container.encode(checklist, forKey: .checklist)
        try container.encode(turnState, forKey: .turnState)
        try container.encode(mode, forKey: .mode)
        try container.encode(title, forKey: .title)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(lastModified, forKey: .lastModified)
    }

    @MainActor
    public var firstUserMessageText: String {
        if let customTitle = title, !customPromptNormalized(customTitle).isEmpty {
            return customTitle
        }
        return messages.first(where: { $0.role == .user })?.content.compactMap { content -> String? in
            if case .text(let t) = content { return t }
            return nil
        }.first ?? "New Conversation"
    }

    @MainActor
    private func customPromptNormalized(_ str: String) -> String {
        str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
