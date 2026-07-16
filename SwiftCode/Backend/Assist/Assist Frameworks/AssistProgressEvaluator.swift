import Foundation

/// Tracks and evaluates progress across autonomous execution iterations
public final class AssistProgressEvaluator {
    private let context: AssistContext
    private var progressHistory: [ProgressSnapshot] = []

    public struct ProgressSnapshot {
        let iteration: Int
        let timestamp: Date
        let goal: String
        let stepsCompleted: Int
        let stepsFailed: Int
        let validationSuccess: Bool
        let feedback: String
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Records a progress snapshot
    public func recordProgress(
        iteration: Int,
        goal: String,
        plan: AssistExecutionPlan,
        validationResult: ValidationResult
    ) {
        let completedSteps = plan.steps.filter { $0.status == .completed }.count
        let failedSteps = plan.steps.filter { $0.status == .failed }.count

        let snapshot = ProgressSnapshot(
            iteration: iteration,
            timestamp: Date(),
            goal: goal,
            stepsCompleted: completedSteps,
            stepsFailed: failedSteps,
            validationSuccess: validationResult.isSuccess,
            feedback: validationResult.feedback
        )

        progressHistory.append(snapshot)
    }

    /// Determines if meaningful progress is being made
    public func isProgressBeingMade() -> Bool {
        guard progressHistory.count >= 3 else { return true }

        let recent = Array(progressHistory.suffix(3))

        // Check if steps are being completed
        let completionTrend = recent.map { $0.stepsCompleted }
        let hasCompletions = completionTrend.contains { $0 > 0 }

        // Check if validation is improving
        let validationTrend = recent.map { $0.validationSuccess }
        let hasSuccess = validationTrend.contains { $0 }

        return hasCompletions || hasSuccess
    }

    /// Gets a summary of progress
    public func getSummary() -> String {
        let totalIterations = progressHistory.count
        let successfulValidations = progressHistory.filter { $0.validationSuccess }.count
        let totalStepsCompleted = progressHistory.reduce(0) { $0 + $1.stepsCompleted }

        return "Progress: \(totalIterations) iterations, \(successfulValidations) successes, \(totalStepsCompleted) steps completed"
    }
}
