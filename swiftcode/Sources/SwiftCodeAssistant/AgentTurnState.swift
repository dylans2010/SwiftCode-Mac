import Foundation

/// What an agent turn is waiting on (Legacy
/// `SwiftCode/Core/AI/Agent/AgentTurnState.swift`, Dylan's own code,
/// ported under MIT). The destination previously tracked this only as
/// a running-task map (`isRunning`) and `Conversation.isActive`; the
/// six-state enum is now session state again.
///
/// Wiring: `CodingAssistantModel` (SwiftCodeIDECore) should drive this
/// from its run loop — `.awaitingModel` while a provider streams,
/// `.executingTools` while tool calls run, `.awaitingUserAnswer` while
/// a `plan-AskUser` question is pending in `PendingQuestionStore`,
/// `.failed` on a terminal `AgentError`. No existing call site was
/// changed to adopt it here; the type is the missing state itself.
public enum AgentTurnState: Codable, Sendable, Equatable {
    case idle
    case awaitingModel
    case executingTools
    case awaitingUserAnswer
    case cancelled
    case failed(AgentError)

    public static func == (lhs: AgentTurnState, rhs: AgentTurnState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.awaitingModel, .awaitingModel), (.executingTools, .executingTools),
             (.awaitingUserAnswer, .awaitingUserAnswer), (.cancelled, .cancelled):
            return true
        case (.failed(let e1), .failed(let e2)):
            return e1.localizedDescription == e2.localizedDescription
        default:
            return false
        }
    }
}
