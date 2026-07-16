import SwiftUI
import Combine
import Observation
import os

@Observable
@MainActor
public class AgentViewModel {
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AgentViewModel")

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
        loadSessions()
    }

    public func startNewSession(mode: AgentChatMode = .chat) {
        logger.info("[startNewSession] Starting new session. Mode: \(mode.rawValue, privacy: .public).")
        let newSession = AgentSession(mode: mode)
        sessions.append(newSession)
        session = newSession
        saveSessions()
    }

    public func selectSession(_ session: AgentSession) {
        logger.info("[selectSession] Selecting session with ID: \(session.id).")
        self.session = session
        saveSessions()
    }

    public func deleteSession(_ session: AgentSession) {
        logger.info("[deleteSession] Deleting session with ID: \(session.id).")
        sessions.removeAll { $0.id == session.id }
        if sessions.isEmpty {
            startNewSession(mode: .chat)
        } else if self.session.id == session.id {
            self.session = sessions.last!
        }
        saveSessions()
    }

    public func sendUserMessage(_ text: String) async {
        logger.info("[sendUserMessage] Sending user message: \(text, privacy: .public).")
        let currentAttachments = attachments
        attachments.removeAll()
        
        session.lastModified = Date()

        do {
            // Re-discover or run turn
            try await orchestrator.runTurn(session: session, userMessage: text, attachments: currentAttachments)
            saveSessions()
        } catch {
            logger.error("[sendUserMessage] Error running turn: \(error.localizedDescription, privacy: .public).")
            session.turnState = .failed(.unknown(error.localizedDescription))
            saveSessions()
        }
    }

    public func sendMessage(_ text: String, attachments: [AgentAttachment] = []) {
        logger.info("[sendMessage] Sending message asynchronously: \(text, privacy: .public).")
        session.lastModified = Date()
        Task {
            do {
                try await orchestrator.runTurn(session: session, userMessage: text, attachments: attachments)
                saveSessions()
            } catch {
                logger.error("[sendMessage] Error running turn asynchronously: \(error.localizedDescription, privacy: .public).")
                session.turnState = .failed(.unknown(error.localizedDescription))
                saveSessions()
            }
        }
    }

    // MARK: - Persistence Placeholders (implemented in Step 4)
    private var persistenceURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("SwiftCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("conversations.json")
    }

    public func saveSessions() {
        logger.info("[saveSessions] Saving conversations to disk.")
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: persistenceURL, options: .atomic)
            // Save selected session ID too
            UserDefaults.standard.set(session.id.uuidString, forKey: "com.swiftcode.agent.selectedSessionID")
            logger.info("[saveSessions] Successfully saved \(self.sessions.count) sessions.")
        } catch {
            logger.error("[saveSessions] Failed to serialize and save sessions: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func loadSessions() {
        logger.info("[loadSessions] Attempting to load conversations from disk.")
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: persistenceURL.path) else {
            logger.info("[loadSessions] No persisted conversations found.")
            return
        }

        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoded = try JSONDecoder().decode([AgentSession].self, from: data)
            if !decoded.isEmpty {
                self.sessions = decoded
                let savedIDString = UserDefaults.standard.string(forKey: "com.swiftcode.agent.selectedSessionID")
                if let savedIDString, let savedID = UUID(uuidString: savedIDString),
                   let matched = sessions.first(where: { $0.id == savedID }) {
                    self.session = matched
                } else {
                    self.session = sessions.last ?? sessions[0]
                }
                logger.info("[loadSessions] Successfully loaded \(self.sessions.count) sessions.")
            }
        } catch {
            logger.error("[loadSessions] Failed to load sessions: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func cancelTurn() {
        session.turnState = .cancelled
    }

    public func cancelTask() {
        cancelTurn()
    }

    public func renameSession(id: UUID, newTitle: String) {
        logger.info("[renameSession] Renaming session ID: \(id) to '\(newTitle, privacy: .public)'.")
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = newTitle.isEmpty ? nil : newTitle
            sessions[idx].lastModified = Date()
            saveSessions()
        }
    }

    public func duplicateSession(_ original: AgentSession) {
        logger.info("[duplicateSession] Duplicating session ID: \(original.id).")
        let copy = AgentSession(
            messages: original.messages,
            checklist: original.checklist,
            turnState: .idle,
            mode: original.mode,
            title: original.title.map { $0 + " Copy" } ?? original.firstUserMessageText + " Copy",
            isPinned: false,
            lastModified: Date()
        )
        sessions.append(copy)
        session = copy
        saveSessions()
    }

    public func togglePinSession(_ target: AgentSession) {
        logger.info("[togglePinSession] Toggling pin on session ID: \(target.id).")
        if let idx = sessions.firstIndex(where: { $0.id == target.id }) {
            sessions[idx].isPinned.toggle()
            sessions[idx].lastModified = Date()
            saveSessions()
        }
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
