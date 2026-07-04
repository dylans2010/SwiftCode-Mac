import Foundation

public struct AgentPendingQuestionSet: Identifiable, Codable, Sendable {
    public let id: UUID
    public let questions: [AgentPendingQuestion]

    public init(id: UUID = UUID(), questions: [AgentPendingQuestion]) {
        self.id = id
        self.questions = questions
    }
}
