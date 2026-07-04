import Foundation

public struct AgentPendingQuestion: Identifiable, Codable, Sendable {
    public let id: UUID
    public let question: String
    public let inputType: InputType

    public enum InputType: Codable, Sendable {
        case text
        case selection(options: [String])
    }

    public init(id: UUID = UUID(), question: String, inputType: InputType) {
        self.id = id
        self.question = question
        self.inputType = inputType
    }
}
