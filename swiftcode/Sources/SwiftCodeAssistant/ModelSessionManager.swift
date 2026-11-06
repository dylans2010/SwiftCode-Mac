// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/ModelSessionManager.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/ModelSessionManager.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - SessionState machine (idle/tearingDown/settingUp/ready/invalid) and activeModelID tracking
//   - LLMService session recreate on switch
//   - DiagnosticEventBus switch logging
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - LLMService — other agent (services-networking-cloud) (`SwiftCode/Features/AI/LLMService.swift`)
// WIRING / REGISTRATION: None (library type) — consumed by Assist session/agent code and, for tool-adjacent types, by SwiftCodeMCP.

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

        // Force clear any old session/provider-specific cached objects
        try? await Task.sleep(nanoseconds: 100_000_000) // Small yield for cleanup

        // 2. TRANSITION-SETUP
        self.state = .settingUp
        logger.log("[switchModel] Setting up new session for model \(cleanModelID)")

        // 3. CONFIRMATION
        // We verify the active model is updated successfully
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
