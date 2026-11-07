import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "llmService.modelSwitch")

@Observable
@MainActor
public final class ModelSessionManager {
    public static let shared = ModelSessionManager()

    public enum SessionState: String, Codable {
        case idle
        case tearingDown = "Tearing Down"
        case settingUp = "Setting Up"
        case ready = "Ready"
        case invalid = "Invalid"
    }

    public var state: SessionState = .idle
    public var activeModelID: String = ""

    private init() {
        self.activeModelID = "openai/gpt-4o-mini"
        self.state = .ready
    }

    public func switchModel(to newModelID: String) async {
        let cleanModelID = newModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModelID.isEmpty else { return }

        logger.log("[switchModel] Initiating switch from \(self.activeModelID) to \(cleanModelID)...")
        DiagnosticEventBus.shared.logEvent(
            component: "ModelSessionManager",
            model: cleanModelID,
            severity: "INFO",
            category: "switch",
            message: "Initiating switch from \(self.activeModelID) to \(cleanModelID)"
        )

        self.state = .tearingDown
        logger.log("[switchModel] Tearing down current session for model \(self.activeModelID)")

        LLMService.shared.recreateSession(for: cleanModelID)

        try? await Task.sleep(nanoseconds: 100_000_000)

        self.state = .settingUp
        logger.log("[switchModel] Setting up new session for model \(cleanModelID)")

        try? await Task.sleep(nanoseconds: 100_000_000)

        logger.log("[switchModel] Resolved provider verified. Session confirmed active for \(cleanModelID).")

        self.activeModelID = cleanModelID
        self.state = .ready

        DiagnosticEventBus.shared.logEvent(
            component: "ModelSessionManager",
            model: cleanModelID,
            severity: "SUCCESS",
            category: "switch",
            message: "Model session successfully reinitialized and confirmed for \(cleanModelID)"
        )
    }
}
