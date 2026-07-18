import Foundation

/// Makes intelligent decisions about execution flow: continue, retry, re-plan, or escalate
@MainActor
public final class AssistAutonomousDecisionEngine {
    private let context: AssistContext

    public enum Decision {
        case continueExecution
        case retryStep(stepIndex: Int)
        case replanTask(feedback: String)
        case optimizeOutput
        case triggerTakeover(reason: String)
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Analyzes execution state and determines next action
    public func decide(
        plan: AssistExecutionPlan,
        validationResult: ValidationResult,
        iterationCount: Int,
        previousFeedbacks: [String]
    ) async -> Decision {
        await context.logger.info("Making autonomous decision (iteration \(iterationCount))", toolId: "DecisionEngine")

        // 1. Check for success
        if validationResult.isSuccess {
            return .continueExecution
        }

        // 2. Check for potential loop (same feedback repeating)
        let feedbackOccurrences = previousFeedbacks.filter { $0 == validationResult.feedback }.count
        if feedbackOccurrences >= 5 {
            // After 5 identical errors, we try to replan by explicitly instructing a change in approach to break the loop.
            return .replanTask(feedback: "Self-Correction: The same failure '\(validationResult.feedback)' has repeated \(feedbackOccurrences) times. You must alter your approach, verify file paths, or gather more context to break the stagnation loop.")
        }

        // 3. Check for excessive iterations without progress - Removed hardcoded cap.
        // Production-grade adaptive orchestration allows execution to continue as long as progress is still possible.

        // 4. Analyze step failures
        let failedSteps = plan.steps.enumerated().filter { $0.element.status == .failed }
        if failedSteps.count == 1 {
            // Single step failure - retry just that step
            return .retryStep(stepIndex: failedSteps[0].offset)
        } else if failedSteps.count > 1 {
            // Multiple failures - replan the entire task
            return .replanTask(feedback: validationResult.feedback)
        }

        // 5. Default to replan with feedback
        return .replanTask(feedback: validationResult.feedback)
    }
}
