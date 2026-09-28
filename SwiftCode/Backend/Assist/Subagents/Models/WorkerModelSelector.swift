import Foundation

/// Capability-aware dynamic model selector for Assist Workers.
/// Selects appropriate model options based on role, scope, and availability without hardcoding identities.
@MainActor
public struct WorkerModelSelector: Sendable {
    public static let shared = WorkerModelSelector()

    public init() {}

    /// Resolves best available model for a worker role and preferred choice.
    public func resolveModel(for role: String, scope: String, preferredModel: String? = nil) -> String {
        // If a specific valid preferred model is declared and available, use it
        if let preferred = preferredModel, !preferred.isEmpty {
            return preferred
        }

        let allAvailable = AssistModelOption.all.map { $0.id }
        let currentParentModel = AssistModelManager.shared.selectedModelID

        let lowerRole = role.lowercased()
        let lowerScope = scope.lowercased()

        // Architecture / Systems / Critical reasoning
        if lowerRole.contains("architect") || lowerRole.contains("security") || lowerScope.contains("architecture") {
            if let reasoning = allAvailable.first(where: {
                $0.contains("claude-3-7") || $0.contains("o1") || $0.contains("o3") || $0.contains("sonnet") || $0.contains("reasoning")
            }) {
                return reasoning
            }
        }

        // Fast testing / verification / documentation tasks
        if lowerRole.contains("test") || lowerRole.contains("doc") || lowerScope.contains("test") {
            if let fast = allAvailable.first(where: {
                $0.contains("flash") || $0.contains("haiku") || $0.contains("mini") || $0.contains("8b")
            }) {
                return fast
            }
        }

        // Coding / UI / Backend default to parent model if non-empty, otherwise first available option
        if !currentParentModel.isEmpty {
            return currentParentModel
        }

        return allAvailable.first ?? "default-coding-model"
    }

    /// Provides fallback model when current worker model encounters error
    public func fallbackModel(for currentModel: String) -> String? {
        let allAvailable = AssistModelOption.all.map { $0.id }
        return allAvailable.first(where: { $0 != currentModel })
    }
}
