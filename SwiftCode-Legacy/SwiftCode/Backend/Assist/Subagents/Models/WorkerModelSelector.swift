import Foundation

@MainActor
public struct WorkerModelSelector: Sendable {
    public static let shared = WorkerModelSelector()

    public init() {}

    public func resolveModel(for role: String, scope: String, preferredModel: String? = nil) -> String {
        let onlyFree = AppSettings.shared.onlyUseFreeModels

        if let preferred = preferredModel, !preferred.isEmpty {
            if !onlyFree || AssistModelEligibilityPolicy.isEligible(modelID: preferred, onlyUseFreeModels: true) {
                return preferred
            }
        }

        let discovered = AssistModelDiscoveryService.shared.discoveredModels.map { $0.modelIdentifier }
        let eligibleDiscovered = AssistModelEligibilityPolicy.filterEligibleModelIDs(discovered, onlyUseFreeModels: onlyFree)

        let allAvailable = AssistModelOption.all.map { $0.id }
        let eligibleStandard = AssistModelEligibilityPolicy.filterEligibleModelIDs(allAvailable, onlyUseFreeModels: onlyFree)
        let candidates = eligibleDiscovered.isEmpty ? eligibleStandard : eligibleDiscovered

        let currentParentModel = AssistModelManager.shared.selectedModelID
        if !currentParentModel.isEmpty && (!onlyFree || AssistModelEligibilityPolicy.isEligible(modelID: currentParentModel, onlyUseFreeModels: true)) {
            return currentParentModel
        }

        let lowerRole = role.lowercased()
        let lowerScope = scope.lowercased()

        if lowerRole.contains("architect") || lowerRole.contains("security") || lowerScope.contains("architecture") {
            if let reasoning = candidates.first(where: {
                $0.contains("claude-3-7") || $0.contains("o1") || $0.contains("o3") || $0.contains("sonnet") || $0.contains("reasoning")
            }) {
                return reasoning
            }
        }

        if lowerRole.contains("test") || lowerRole.contains("doc") || lowerScope.contains("test") {
            if let fast = candidates.first(where: {
                $0.contains("flash") || $0.contains("haiku") || $0.contains("mini") || $0.contains("8b")
            }) {
                return fast
            }
        }

        return candidates.first ?? (onlyFree ? "openrouter/free" : "default-coding-model")
    }

    public func fallbackModel(for currentModel: String) -> String? {
        let onlyFree = AppSettings.shared.onlyUseFreeModels
        let discovered = AssistModelDiscoveryService.shared.discoveredModels.map { $0.modelIdentifier }
        let candidates = discovered.isEmpty ? AssistModelOption.all.map { $0.id } : discovered
        let eligible = AssistModelEligibilityPolicy.filterEligibleModelIDs(candidates, onlyUseFreeModels: onlyFree)
        return eligible.first(where: { $0 != currentModel })
    }
}
