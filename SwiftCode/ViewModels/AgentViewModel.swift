import SwiftUI
import Combine

@MainActor
public class AgentViewModel: ObservableObject {
    @Published public var session: AgentSession
    private let orchestrator = AgentOrchestrator()

    public init(session: AgentSession = .init()) {
        self.session = session
    }

    public func sendMessage(_ text: String, attachments: [AgentAttachment] = []) {
        Task {
            do {
                try await orchestrator.runTurn(session: &session, userMessage: text, attachments: attachments)
            } catch {
                session.turnState = .failed(.unknown(error.localizedDescription))
            }
        }
    }

    public func cancelTurn() {
        session.turnState = .cancelled
    }

    public func submitAnswer(_ answer: String) {
        guard let lastToolCall = findLastUnansweredToolCall() else { return }
        Task {
            do {
                try await orchestrator.resumeTurn(session: &session, result: answer, toolCallId: lastToolCall.id)
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
                try await orchestrator.resumeTurn(session: &session, result: result, toolCallId: lastToolCall.id)
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
