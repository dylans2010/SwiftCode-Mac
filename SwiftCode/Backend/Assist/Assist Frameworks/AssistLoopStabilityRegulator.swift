import Foundation

/// Regulates autonomous loop behavior to prevent instability
@MainActor
public final class AssistLoopStabilityRegulator {
    private let context: AssistContext
    private var executionHistory: [ExecutionRecord] = []

    public struct ExecutionRecord {
        let iteration: Int
        let timestamp: Date
        let goal: String
        let planHash: Int
        let validationFeedback: String
        let wasSuccessful: Bool
    }

    public enum StabilityIssue {
        case infiniteLoop(reason: String)
        case oscillation(pattern: String)
        case noProgress(iterations: Int)
        case repetitiveActions
        case none
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Records an execution iteration
    public func recordExecution(
        iteration: Int,
        goal: String,
        plan: AssistExecutionPlan,
        validationResult: ValidationResult
    ) {
        let planHash = computePlanHash(plan)
        let record = ExecutionRecord(
            iteration: iteration,
            timestamp: Date(),
            goal: goal,
            planHash: planHash,
            validationFeedback: validationResult.feedback,
            wasSuccessful: validationResult.isSuccess
        )
        executionHistory.append(record)
    }

    /// Detects stability issues in execution loop
    public func detectStabilityIssues() async -> StabilityIssue {
        guard executionHistory.count >= 3 else { return .none }

        // Check 1: Infinite loop (identical plans repeating)
        let recentPlans = Array(executionHistory.suffix(8))
        let planHashes = recentPlans.map { $0.planHash }
        if Set(planHashes).count == 1 && recentPlans.count >= 8 {
            await context.logger.error("Infinite loop detected: Identical plans repeating", toolId: "StabilityRegulator")
            return .infiniteLoop(reason: "Same plan generated 8 times in a row")
        }

        // Check 2: Oscillation (alternating between 2-3 states)
        if recentPlans.count >= 6 {
            let pattern = recentPlans.map { $0.planHash }
            if isOscillating(pattern) {
                await context.logger.error("Oscillation detected: Plans alternating between states", toolId: "StabilityRegulator")
                return .oscillation(pattern: "Plans cycling between multiple states without progress")
            }
        }

        // Check 3: No progress (all recent iterations failing)
        let recentResults = Array(executionHistory.suffix(15))
        let allFailing = recentResults.allSatisfy { !$0.wasSuccessful }
        if allFailing && recentResults.count >= 15 {
            await context.logger.error("No progress: \(recentResults.count) consecutive failures", toolId: "StabilityRegulator")
            return .noProgress(iterations: recentResults.count)
        }

        // Check 4: Repetitive feedback (same errors repeating)
        let recentFeedbacks = Array(executionHistory.suffix(8)).map { $0.validationFeedback }
        let uniqueFeedbacks = Set(recentFeedbacks)
        if uniqueFeedbacks.count == 1 && recentFeedbacks.count >= 5 {
            await context.logger.warning("Repetitive actions detected: Same feedback repeating", toolId: "StabilityRegulator")
            return .repetitiveActions
        }

        return .none
    }

    private func computePlanHash(_ plan: AssistExecutionPlan) -> Int {
        var hasher = Hasher()
        for step in plan.steps {
            hasher.combine(step.toolId)
            hasher.combine(step.description)
        }
        return hasher.finalize()
    }

    private func isOscillating(_ pattern: [Int]) -> Bool {
        guard pattern.count >= 4 else { return false }
        let tail = Array(pattern.suffix(6))
        let tailCount = tail.count

        // Check 2-state oscillation on the tail: [..., A, B, A, B]
        if tailCount >= 4 {
            let n = tailCount
            if tail[n - 4] == tail[n - 2] && tail[n - 3] == tail[n - 1] && tail[n - 4] != tail[n - 3] {
                return true
            }
        }

        // Check 3-state oscillation on the tail: [A, B, C, A, B, C]
        if tailCount >= 6 {
            if tail[0] == tail[3] && tail[1] == tail[4] && tail[2] == tail[5] {
                return true
            }
        }

        return false
    }

    /// Resets stability tracking
    public func reset() {
        executionHistory.removeAll()
    }
}
