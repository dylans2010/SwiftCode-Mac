// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/AssistModelManager.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/AssistModelManager.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - AssistModelManager singleton and selectedModelID/health state
//   - overrideModelID / notifyFallbackTransition / clearFallbackNotification
// ADAPTATIONS:
//   - Combine -> Observation (destination convention, cf. TasksAIPlanner.swift): `: ObservableObject` removed, class marked @Observable, @Published vars are plain stored vars, `import Observation` added. @MainActor NOT added — wiring to decide.
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AgentModelAdapter — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AgentModelAdapter.swift`)
//   - AppSettings — UNOWNED (no worklist) (`SwiftCode/Models/AppSettings.swift`)
//   - AssistModelProvider — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AssistModels.swift`)
//   - ModelFailureClassification — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AgentModelAdapter.swift`)
//   - ModelHealthEntry — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AgentModelAdapter.swift`)
//   - OfflineFallbackManager — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AgentModelAdapter.swift`)
// WIRING / REGISTRATION: None (library type) — consumed by Assist session/agent code and, for tool-adjacent types, by SwiftCodeMCP.

import Foundation
import Observation

@MainActor
@Observable
public final class AssistModelManager {
    public static let shared = AssistModelManager()

    public var customModelID: String {
        didSet {
            UserDefaults.standard.set(customModelID, forKey: "assist.customModelID")
        }
    }

    public var lastFallbackMessage: String?

    private init() {
        self.customModelID = UserDefaults.standard.string(forKey: "assist.customModelID") ?? ""
    }

    public var selectedModelID: String {
        let appSetting = AppSettings.shared.selectedAssistModelID
        if !appSetting.isEmpty {
            return AssistModelOption.resolve(id: appSetting)
        }
        if !customModelID.isEmpty {
            return AssistModelOption.resolve(id: customModelID)
        }
        return ""
    }

    public var selectedModelSpecification: ModelSpecification {
        return AgentModelAdapter.shared.specification(for: selectedModelID)
    }

    public var selectedModelContextBudget: AgentModelContextBudget {
        return AgentModelAdapter.shared.contextBudget(for: selectedModelID)
    }

    public var selectedModelHealth: ModelHealthEntry {
        return OfflineFallbackManager.shared.healthEntry(for: selectedModelID)
    }

    public var isSelectedModelInCooldown: Bool {
        return !selectedModelHealth.isHealthy()
    }

    public func overrideModelID(for provider: AssistModelProvider) -> String {
        return selectedModelID
    }

    public func notifyFallbackTransition(classification: ModelFailureClassification, fallbackModel: String) {
        let message = OfflineFallbackManager.shared.fallbackTransitionMessage(
            for: classification,
            fallbackModel: fallbackModel
        )
        lastFallbackMessage = message
    }

    public func clearFallbackNotification() {
        lastFallbackMessage = nil
    }
}
