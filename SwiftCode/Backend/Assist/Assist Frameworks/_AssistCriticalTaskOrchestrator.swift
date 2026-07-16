import Foundation

/// [CRITICAL SYSTEM FILE] - HIGH RISK
/// Manages the breakdown of high-level goals into executable tasks and coordinates their execution.
public final class _AssistCriticalTaskOrchestrator {
    private let context: AssistContext
    private let planner: TasksAIPlanner
    private let executionEngine: _AssistCriticalExecutionEngine

    @MainActor
    public init(context: AssistContext) {
        self.context = context
        self.planner = TasksAIPlanner.shared
        self.executionEngine = _AssistCriticalExecutionEngine(context: context)
    }

    /// Creates a structured plan for the given intent.
    @MainActor
    public func createPlan(for intent: String) async throws -> AssistExecutionPlan {
        return try await planner.generatePlan(intent: intent, context: context)
    }

    /// Executes the given plan step-by-step.
    @MainActor
    public func execute(plan: inout AssistExecutionPlan) async throws {
        try await executionEngine.execute(plan: &plan)
    }
}
