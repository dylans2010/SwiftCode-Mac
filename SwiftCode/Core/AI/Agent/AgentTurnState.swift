import Foundation

public enum AgentTurnState: Codable, Sendable, Equatable {
    case idle
    case awaitingModel
    case executingTools
    case awaitingUserAnswer
    case cancelled
    case failed(AgentError)

    public static func == (lhs: AgentTurnState, rhs: AgentTurnState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.awaitingModel, .awaitingModel), (.executingTools, .executingTools), (.awaitingUserAnswer, .awaitingUserAnswer), (.cancelled, .cancelled):
            return true
        case (.failed(let e1), .failed(let e2)):
            return e1.localizedDescription == e2.localizedDescription
        default:
            return false
        }
    }
}
