import Foundation

@MainActor
public struct WorkerModelSelector: Sendable {
    public static let shared = WorkerModelSelector()

    public let onlyUseFreeModels: Bool
    public let parentModelID: String
    public let standardModelIDs: [String]
    public let discoveredModelIDs: @Sendable () async -> [String]

    public init(
        onlyUseFreeModels: Bool = false,
        parentModelID: String = "",
        standardModelIDs: [String] = [],
        discoveredModelIDs: @escaping @Sendable () async -> [String] = { [] }
    ) {
        self.onlyUseFreeModels = onlyUseFreeModels
        self.parentModelID = parentModelID
        self.standardModelIDs = standardModelIDs
        self.discoveredModelIDs = discoveredModelIDs
    }

    public func resolveModel(for role: String, scope: String, preferredModel: String? = nil) async -> String {
        let onlyFree = onlyUseFreeModels

        if let preferred = preferredModel, !preferred.isEmpty {
            if !onlyFree || AssistModelEligibilityPolicy.isEligible(modelID: preferred, onlyUseFreeModels: true) {
                return preferred
            }
        }

        let discovered = await discoveredModelIDs()
        let eligibleDiscovered = AssistModelEligibilityPolicy.filterEligibleModelIDs(discovered, onlyUseFreeModels: onlyFree)

        let eligibleStandard = AssistModelEligibilityPolicy.filterEligibleModelIDs(standardModelIDs, onlyUseFreeModels: onlyFree)
        let candidates = eligibleDiscovered.isEmpty ? eligibleStandard : eligibleDiscovered

        let currentParentModel = parentModelID
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

    public func fallbackModel(for currentModel: String) async -> String? {
        let onlyFree = onlyUseFreeModels
        let discovered = await discoveredModelIDs()
        let candidates = discovered.isEmpty ? standardModelIDs : discovered
        let eligible = AssistModelEligibilityPolicy.filterEligibleModelIDs(candidates, onlyUseFreeModels: onlyFree)
        return eligible.first(where: { $0 != currentModel })
    }
}
