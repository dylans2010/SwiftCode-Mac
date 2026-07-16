import SwiftUI
import Combine
import Observation

public enum AIAssistantMode: String, CaseIterable, Codable, Sendable {
    case chat = "Chat"
    case agent = "Agent"
}

@Observable
@MainActor
public class AgentViewModel {
    public var session: AgentSession
    public var attachments: [AgentAttachment] = []
    public var mode: AIAssistantMode = .chat
    public var projectURL: URL?

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
        
        var queryText = text
        if mode == .chat {
            let context = await gatherCodebaseContext(for: text)
            if !context.isEmpty {
                queryText += context
            }
        }

        do {
            try await orchestrator.runTurn(session: session, userMessage: queryText, attachments: currentAttachments, mode: mode)
        } catch {
            session.turnState = .failed(.unknown(error.localizedDescription))
        }
    }

    public func sendMessage(_ text: String, attachments: [AgentAttachment] = []) {
        Task {
            var queryText = text
            if mode == .chat {
                let context = await gatherCodebaseContext(for: text)
                if !context.isEmpty {
                    queryText += context
                }
            }
            do {
                try await orchestrator.runTurn(session: session, userMessage: queryText, attachments: attachments, mode: mode)
            } catch {
                session.turnState = .failed(.unknown(error.localizedDescription))
            }
        }
    }

    private func gatherCodebaseContext(for query: String) async -> String {
        guard let projectURL = self.projectURL else { return "" }

        let searchResults = await CodeIndexService.shared.searchProject(query: query, at: projectURL)
        if searchResults.isEmpty { return "" }

        // Take top 5 search results to avoid hitting token limits, and format them nicely
        var context = "\n\n[Codebase Context Integration]\nRelevant files found in the project:\n"
        for result in searchResults.prefix(5) {
            context += "• File: \(result.filePath) (Line \(result.lineNumber)):\n```swift\n\(result.snippet)\n```\n"
        }
        return context
    }

    public func cancelTurn() {
        Task {
            await orchestrator.cancel()
        }
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
