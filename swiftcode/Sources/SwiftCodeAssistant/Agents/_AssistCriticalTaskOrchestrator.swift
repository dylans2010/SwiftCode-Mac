import Foundation

@MainActor
public final class _AssistCriticalTaskOrchestrator {
    private let context: AssistContext
    private let planner: TasksAIPlanner
    private let executionEngine: _AssistCriticalExecutionEngine

    public init(context: AssistContext) {
        self.context = context
        self.planner = TasksAIPlanner.shared
        self.executionEngine = _AssistCriticalExecutionEngine(context: context)
    }

    public func createPlan(for intent: String) async throws -> AssistExecutionPlan {
        return try await planner.generatePlan(intent: intent, context: context)
    }

    public func execute(plan: inout AssistExecutionPlan) async throws {
        try await executionEngine.execute(plan: &plan)
    }
}
