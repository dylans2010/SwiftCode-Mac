import Foundation

/// One task in an agent checklist (Legacy
/// `SwiftCode/Core/AI/Agent/AgentChecklistTask.swift`, Dylan's own code,
/// ported under MIT).
public struct AgentChecklistTask: Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public var status: AgentChecklistTaskStatus
    public let detail: String?

    public init(id: String, title: String, status: AgentChecklistTaskStatus, detail: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public enum AgentChecklistTaskStatus: String, Codable, Sendable {
    case queued
    case inProgress = "in_progress"
    case completed
    case failed
}

/// The whole checklist state of an agent turn (Legacy
/// `AgentChecklistState.swift`).
public struct AgentChecklistState: Codable, Sendable {
    public var tasks: [AgentChecklistTask]

    public init(tasks: [AgentChecklistTask]) {
        self.tasks = tasks
    }
}

/// Structured content of one agent message (Legacy
/// `SwiftCode/Core/AI/Agent/AgentMessageContent.swift`, Dylan's own code,
/// ported under MIT).
///
/// The destination's `ConversationMessage` flattens every message to
/// text; the typed cases below restore what that flattening lost:
/// image content, typed tool calls/results, pending questions and
/// checklist updates. `AgentToolCall`, `AgentToolResult` and
/// `AgentChecklistState` live in `AgentError.swift` /
/// this file; the MCP layer's `MCPToolCall` / `MCPToolResult` are the
/// transport forms, not these.
public enum AgentMessageContent: Codable, Sendable {
    case text(String)
    case image(data: Data, mimeType: String)
    case toolCall(AgentToolCall)
    case toolResult(AgentToolResult)
    case pendingQuestion(AgentPendingQuestion)
    case pendingQuestionSet(AgentPendingQuestionSet)
    case checklistUpdate(AgentChecklistState)
}

/// One agent message (Legacy `SwiftCode/Core/AI/Agent/AgentMessage.swift`).
///
/// Adaptation: Legacy's role was `AIMessage.Role`; the destination's
/// role type is `ChatRole` (`system` / `user` / `assistant`), so the
/// port uses that. `ConversationMessage` remains the persisted chat
/// form; `AgentMessage` is the structured turn form for agent runs
/// that need typed content.
public struct AgentMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public let role: ChatRole
    public var content: [AgentMessageContent]
    public let timestamp: Date

    public init(id: UUID = UUID(), role: ChatRole, content: [AgentMessageContent], timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    /// The message's text parts joined, for providers that only take text.
    public var text: String {
        content.compactMap { item -> String? in
            if case .text(let text) = item { return text }
            return nil
        }.joined(separator: " ")
    }
}
