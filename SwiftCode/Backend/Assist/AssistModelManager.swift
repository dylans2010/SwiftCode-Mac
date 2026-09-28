import Foundation

@MainActor
public final class AssistModelManager: ObservableObject {
    public static let shared = AssistModelManager()

    @Published public var customModelID: String {
        didSet {
            UserDefaults.standard.set(customModelID, forKey: "assist.customModelID")
        }
    }

    @Published public var lastFallbackMessage: String?

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
        return AssistModelOption.swiftCodeBalanced.id
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
