import SwiftUI
import Combine
import Observation

@Observable
@MainActor
public class AgentViewModel {
    public var session: AgentSession
    public var attachments: [AgentAttachment] = []
    
    public var isProcessing: Bool {
        switch session.turnState {
        case .awaitingModel, .executingTools:
            return true
        default:
            return false
        }
    }

    private let orchestrator = AgentOrchestrator()

    public init(session: AgentSession = .init()) {
        self.session = session
    }

    public func sendUserMessage(_ text: String) async {
        let currentAttachments = attachments
        attachments.removeAll()
        
        do {
            var localSession = session
            try await orchestrator.runTurn(session: &localSession, userMessage: text, attachments: currentAttachments)
            session = localSession
        } catch {
            session.turnState = .failed(.unknown(error.localizedDescription))
        }
    }

    public func sendMessage(_ text: String, attachments: [AgentAttachment] = []) {
        Task {
            do {
                var localSession = session
                try await orchestrator.runTurn(session: &localSession, userMessage: text, attachments: attachments)
                session = localSession
            } catch {
                session.turnState = .failed(.unknown(error.localizedDescription))
            }
        }
    }

    public func cancelTurn() {
        session.turnState = .cancelled
    }

    public func cancelTask() {
        cancelTurn()
    }

    public func submitAnswer(_ answer: String) {
        guard let lastToolCall = findLastUnansweredToolCall() else { return }
        Task {
            do {
                var localSession = session
                try await orchestrator.resumeTurn(session: &localSession, result: answer, toolCallId: lastToolCall.id)
                session = localSession
            } catch {
                session.turnState = .failed(.unknown(error.localizedDescription))
            }
        }
    }

    public func submitMultipleAnswers(_ answers: [UUID: String]) {
        guard let lastToolCall = findLastUnansweredToolCall() else { return }
        let jsonAnswers = try? JSONSerialization.data(withJSONObject: answers.reduce(into: [String: String]()) { $0[$1.key.uuidString] = $1.value })
        let result = String(data: jsonAnswers ?? Data(), encoding: .utf8) ?? "{}"

        Task {
            do {
                var localSession = session
                try await orchestrator.resumeTurn(session: &localSession, result: result, toolCallId: lastToolCall.id)
                session = localSession
            } catch {
                session.turnState = .failed(.unknown(error.localizedDescription))
            }
        }
    }

    private func findLastUnansweredToolCall() -> AgentToolCall? {
        for message in session.messages.reversed() {
            for content in message.content {
                if case .toolCall(let call) = content {
                    if call.name == "ask_user" || call.name == "questions_handle" {
                        // Check if there is already a result for this id
                        let hasResult = session.messages.contains { m in
                            m.content.contains { c in
                                if case .toolResult(let res) = c { return res.toolCallId == call.id }
                                return false
                            }
                        }
                        if !hasResult { return call }
                    }
                }
            }
        }
        return nil
    }
}
