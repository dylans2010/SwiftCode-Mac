// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Assist Frameworks/_AssistCriticalTaskOrchestrator.swift`
// (Legacy main d51a8f0d; Dylan's own code, direct port authorised under MIT).
// Target: SwiftCodeAssistant. NOT YET COMPILABLE on its own: the types listed
// under MISSING DEPENDENCIES below do not exist in the destination yet.
// NOTE: the reconciliation table listed this file as NO_TYPES, but it does
// declare a top-level type — `_AssistCriticalTaskOrchestrator` — which is
// ported here in full. The leading underscore is a Legacy naming quirk;
// the type name is kept as-is (no destination collision, verified by grep).
//
// MISSING DEPENDENCIES (Legacy-only; each needs its own port before this file compiles):
//   - RESOLVED 2026-11-06: AssistContext and AssistExecutionPlan are now staged in
//     AssistModels.swift by the parallel port (see _notes/agent-models-decisions.md).
//   - RESOLVED 2026-11-06 (agent-frameworks pass): TasksAIPlanner is now staged in
//     SwiftCodeAssistant (TasksAIPlanner.swift).
//   - _AssistCriticalExecutionEngine — staged alongside this file in this same batch

import Foundation

/// [CRITICAL SYSTEM FILE] - HIGH RISK
/// Manages the breakdown of high-level goals into executable tasks and coordinates their execution.
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

    /// Creates a structured plan for the given intent.
    public func createPlan(for intent: String) async throws -> AssistExecutionPlan {
        return try await planner.generatePlan(intent: intent, context: context)
    }

    /// Executes the given plan step-by-step.
    public func execute(plan: inout AssistExecutionPlan) async throws {
        try await executionEngine.execute(plan: &plan)
    }
}
