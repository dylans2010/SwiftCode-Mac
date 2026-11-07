import Foundation

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

    public func decide(
        plan: AssistExecutionPlan,
        validationResult: ValidationResult,
        iterationCount: Int,
        previousFeedbacks: [String]
    ) async -> Decision {
        await context.logger.info("Making autonomous decision (iteration \(iterationCount))", toolId: "DecisionEngine")

        if validationResult.isSuccess {
            return .continueExecution
        }

        let feedbackOccurrences = previousFeedbacks.filter { $0 == validationResult.feedback }.count
        if feedbackOccurrences >= 5 {
            return .replanTask(feedback: "Self-Correction: The same failure '\(validationResult.feedback)' has repeated \(feedbackOccurrences) times. You must alter your approach, verify file paths, or gather more context to break the stagnation loop.")
        }

        let failedSteps = plan.steps.enumerated().filter { $0.element.status == .failed }
        if failedSteps.count == 1 {
            return .retryStep(stepIndex: failedSteps[0].offset)
        } else if failedSteps.count > 1 {
            return .replanTask(feedback: validationResult.feedback)
        }

        return .replanTask(feedback: validationResult.feedback)
    }
}
