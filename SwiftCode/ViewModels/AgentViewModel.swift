import SwiftUI
import Combine
import Observation

@Observable
@MainActor
public class AgentViewModel {
    public var session: AgentSession
    public var sessions: [AgentSession] = []
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
        self.sessions = [session]
    }

    public func startNewSession(mode: AgentChatMode = .chat) {
        let newSession = AgentSession(mode: mode)
        sessions.append(newSession)
        session = newSession
    }

    public func selectSession(_ session: AgentSession) {
        self.session = session
    }

    public func deleteSession(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
        if sessions.isEmpty {
            startNewSession(mode: .chat)
        } else if self.session.id == session.id {
            self.session = sessions.last!
        }
    }

    public func sendUserMessage(_ text: String) async {
        let currentAttachments = attachments
        attachments.removeAll()
        
        do {
            try await orchestrator.runTurn(session: session, userMessage: text, attachments: currentAttachments)
        } catch {
            session.turnState = .failed(.unknown(error.localizedDescription))
        }
    }

    public func sendMessage(_ text: String, attachments: [AgentAttachment] = []) {
        Task {
            do {
                try await orchestrator.runTurn(session: session, userMessage: text, attachments: attachments)
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
                try await orchestrator.resumeTurn(session: session, result: answer, toolCallId: lastToolCall.id)
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
                try await orchestrator.resumeTurn(session: session, result: result, toolCallId: lastToolCall.id)
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
