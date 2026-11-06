import Foundation

// MARK: - Worker Model Selector (ported from Legacy, adapted)
//
// Ported from Legacy (Dylan's own code; direct port authorised under
// MIT): `SwiftCode/Backend/Assist/Subagents/Models/WorkerModelSelector.swift`
// — capability-aware dynamic model selection for Assist Workers.
// The selection logic (preferred model → discovered candidates →
// parent model → role/scope heuristics → literal fallbacks) is
// Legacy-verbatim.
//
// Destination: `SwiftCodeAssistant` (SwiftPM target, depends only on
// `SwiftCodeSubprocess`). No new imports: Foundation only.
// `AssistModelEligibilityPolicy` is used directly — it already exists
// in the destination (`AssistModelRouting.swift`) with Legacy's exact
// API (`isEligible(modelID:onlyUseFreeModels:)`,
// `filterEligibleModelIDs(_:onlyUseFreeModels:)`).
//
// Adaptations (Legacy dependencies with no destination equivalent —
// each becomes a narrow injected seam instead of an invented fake):
//   * `AppSettings.shared.onlyUseFreeModels` — no `AppSettings`
//     singleton exists in the destination. The equivalent setting is
//     `AssistantSettings.onlyUseFreeModels`, a value-struct property
//     owned by the host. Injected as `onlyUseFreeModels`.
//   * `AssistModelDiscoveryService.shared.discoveredModels` — the
//     destination service exists (`AssistModelDiscovery.swift`) but
//     is an actor with no `.shared`, constructed with a `SecretStore`,
//     and its `discoveredModels` is actor-isolated. Injected as an
//     async `discoveredModelIDs` closure; the host wires it to
//     `await service.discoveredModels.map { $0.modelIdentifier }`.
//     This is also why `resolveModel` / `fallbackModel` are async
//     here while Legacy's were sync.
//   * `AssistModelOption.all` — no destination equivalent (no
//     standard model list exists). Injected as `standardModelIDs`.
//   * `AssistModelManager.shared.selectedModelID` — no destination
//     equivalent (the manager singleton was not ported; the selected
//     model lives in host-owned `AssistantSettings`). Injected as
//     `parentModelID`.
// `WorkerModelSelector.shared` is the default-wired instance (no
// discovery source, no parent model); the host should construct a
// wired instance via `init` for real use.

/// Capability-aware dynamic model selector for Assist Workers.
/// Selects appropriate model options based on role, scope, and availability without hardcoding identities.
@MainActor
public struct WorkerModelSelector: Sendable {
    public static let shared = WorkerModelSelector()

    /// Whether only free models are eligible (Legacy:
    /// `AppSettings.shared.onlyUseFreeModels`).
    public let onlyUseFreeModels: Bool
    /// The parent session's selected model ID, when the host has one
    /// (Legacy: `AssistModelManager.shared.selectedModelID`).
    public let parentModelID: String
    /// The standard (non-discovered) model IDs to fall back to when
    /// discovery has nothing eligible (Legacy: `AssistModelOption.all`
    /// mapped to `.id`).
    public let standardModelIDs: [String]
    /// The currently discovered model IDs (Legacy:
    /// `AssistModelDiscoveryService.shared.discoveredModels` mapped to
    /// `.modelIdentifier`). Async because the destination discovery
    /// service is an actor.
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

    /// Resolves best available model for a worker role and preferred choice.
    public func resolveModel(for role: String, scope: String, preferredModel: String? = nil) async -> String {
        let onlyFree = onlyUseFreeModels

        // If a specific valid preferred model is declared and eligible, use it
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

        // Architecture / Systems / Critical reasoning
        if lowerRole.contains("architect") || lowerRole.contains("security") || lowerScope.contains("architecture") {
            if let reasoning = candidates.first(where: {
                $0.contains("claude-3-7") || $0.contains("o1") || $0.contains("o3") || $0.contains("sonnet") || $0.contains("reasoning")
            }) {
                return reasoning
            }
        }

        // Fast testing / verification / documentation tasks
        if lowerRole.contains("test") || lowerRole.contains("doc") || lowerScope.contains("test") {
            if let fast = candidates.first(where: {
                $0.contains("flash") || $0.contains("haiku") || $0.contains("mini") || $0.contains("8b")
            }) {
                return fast
            }
        }

        return candidates.first ?? (onlyFree ? "openrouter/free" : "default-coding-model")
    }

    /// Provides fallback model when current worker model encounters error
    public func fallbackModel(for currentModel: String) async -> String? {
        let onlyFree = onlyUseFreeModels
        let discovered = await discoveredModelIDs()
        let candidates = discovered.isEmpty ? standardModelIDs : discovered
        let eligible = AssistModelEligibilityPolicy.filterEligibleModelIDs(candidates, onlyUseFreeModels: onlyFree)
        return eligible.first(where: { $0 != currentModel })
    }
}
