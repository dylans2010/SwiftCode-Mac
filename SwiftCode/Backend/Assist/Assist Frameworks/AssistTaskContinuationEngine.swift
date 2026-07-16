import Foundation

/// Determines whether to continue autonomous execution and generates next tasks
public final class AssistTaskContinuationEngine {
    private let context: AssistContext
    private var completedTaskCount = 0

    public init(context: AssistContext) {
        self.context = context
    }

    /// Decides if autonomous execution should continue
    public func shouldContinue(currentGoal: String, completedPlan: AssistExecutionPlan) async -> Bool {
        let takeoverEnabled = UserDefaults.standard.bool(forKey: "assist.takeoverEnabled")
        guard takeoverEnabled else { return false }

        completedTaskCount += 1
        await context.logger.info("Completed task #\(completedTaskCount). Evaluating continuation...", toolId: "TaskContinuation")

        // Continue if under reasonable task count (prevent runaway execution)
        return completedTaskCount < 50
    }

    /// Generates the next task to execute
    public func generateNextTask(previousGoal: String, completedPlan: AssistExecutionPlan, expandedGoals: [String]) async -> String? {
        guard !expandedGoals.isEmpty else {
            await context.logger.info("No expanded goals available, ending autonomous execution", toolId: "TaskContinuation")
            return nil
        }

        // Take the first expanded goal
        let nextGoal = expandedGoals[0]
        await context.logger.info("Next autonomous task: \(nextGoal)", toolId: "TaskContinuation")
        return nextGoal
    }

    /// Resets the continuation state
    public func reset() {
        completedTaskCount = 0
    }
}
