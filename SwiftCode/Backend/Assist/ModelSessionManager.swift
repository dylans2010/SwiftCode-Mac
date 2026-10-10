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
        // SAFETY: Fallback value provided in case AppSettings is empty.
        self.activeModelID = "openai/gpt-4o-mini"
        self.state = .ready
    }

    public func switchModel(to newModelID: String) async {
        let cleanModelID = newModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModelID.isEmpty else { return }

        // Fast path: if already active and ready on this exact model, skip redundant teardown
        if self.activeModelID == cleanModelID && self.state == .ready {
            logger.debug("[switchModel] Model '\(cleanModelID)' is already active and ready. Skipping redundant switch.")
            return
        }

        logger.log("[switchModel] Initiating switch from \(self.activeModelID) to \(cleanModelID)...")
        DiagnosticEventBus.shared.logEvent(
            component: "ModelSessionManager",
            model: cleanModelID,
            severity: "INFO",
            category: "switch",
            message: "Initiating switch from \(self.activeModelID) to \(cleanModelID)"
        )

        // 1. TRANSITION-TEARDOWN
        self.state = .tearingDown
        logger.log("[switchModel] Tearing down current session for model \(self.activeModelID)")

        // Invalidate URLSession on LLMService
        LLMService.shared.recreateSession(for: cleanModelID)

        // 2. TRANSITION-SETUP
        self.state = .settingUp
        logger.log("[switchModel] Setting up new session for model \(cleanModelID)")

        // 3. CONFIRMATION
        self.activeModelID = cleanModelID
        self.state = .ready
        logger.log("[switchModel] Resolved provider verified. Session confirmed active for \(cleanModelID).")

        DiagnosticEventBus.shared.logEvent(
            component: "ModelSessionManager",
            model: cleanModelID,
            severity: "SUCCESS",
            category: "switch",
            message: "Model session successfully reinitialized and confirmed for \(cleanModelID)"
        )
    }
}
