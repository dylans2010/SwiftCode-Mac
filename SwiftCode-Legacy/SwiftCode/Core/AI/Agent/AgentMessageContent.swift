import Foundation

public enum AgentMessageContent: Codable, Sendable {
    case text(String)
    case image(data: Data, mimeType: String)
    case toolCall(AgentToolCall)
    case toolResult(AgentToolResult)
    case pendingQuestion(AgentPendingQuestion)
    case pendingQuestionSet(AgentPendingQuestionSet)
    case checklistUpdate(AgentChecklistState)
}
