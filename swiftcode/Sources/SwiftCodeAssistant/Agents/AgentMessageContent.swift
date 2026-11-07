import Foundation

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

public struct AgentChecklistState: Codable, Sendable {
    public var tasks: [AgentChecklistTask]

    public init(tasks: [AgentChecklistTask]) {
        self.tasks = tasks
    }
}

public enum AgentMessageContent: Codable, Sendable {
    case text(String)
    case image(data: Data, mimeType: String)
    case toolCall(AgentToolCall)
    case toolResult(AgentToolResult)
    case pendingQuestion(AgentPendingQuestion)
    case pendingQuestionSet(AgentPendingQuestionSet)
    case checklistUpdate(AgentChecklistState)
}

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

    public var text: String {
        content.compactMap { item -> String? in
            if case .text(let text) = item { return text }
            return nil
        }.joined(separator: " ")
    }
}
