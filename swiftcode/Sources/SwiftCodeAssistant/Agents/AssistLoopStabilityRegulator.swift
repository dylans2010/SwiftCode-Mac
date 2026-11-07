import Foundation

@MainActor
public final class AssistLoopStabilityRegulator {
    private let context: AssistContext
    private var executionHistory: [ExecutionRecord] = []

    private static let maxHistorySize = 50

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
        if executionHistory.count > Self.maxHistorySize {
            executionHistory.removeFirst(executionHistory.count - Self.maxHistorySize)
        }

        if validationResult.isSuccess {
            AssistTakeoverSessionState.shared.recordSuccess()
        } else {
            AssistTakeoverSessionState.shared.recordFailure()
        }
    }

    public var consecutiveFailures: Int {
        var count = 0
        for record in executionHistory.reversed() {
            if record.wasSuccessful { break }
            count += 1
        }
        return count
    }

    public func detectStabilityIssues() async -> StabilityIssue {
        guard executionHistory.count >= 3 else { return .none }

        let recentPlans = Array(executionHistory.suffix(8))
        let planHashes = recentPlans.map { $0.planHash }
        if Set(planHashes).count == 1 && recentPlans.count >= 8 {
            await context.logger.error("Infinite loop detected: Identical plans repeating", toolId: "StabilityRegulator")
            return .infiniteLoop(reason: "Same plan generated 8 times in a row")
        }

        if recentPlans.count >= 6 {
            let pattern = recentPlans.map { $0.planHash }
            if isOscillating(pattern) {
                await context.logger.error("Oscillation detected: Plans alternating between states", toolId: "StabilityRegulator")
                return .oscillation(pattern: "Plans cycling between multiple states without progress")
            }
        }

        let recentResults = Array(executionHistory.suffix(15))
        let allFailing = recentResults.allSatisfy { !$0.wasSuccessful }
        if allFailing && recentResults.count >= 15 {
            await context.logger.error("No progress: \(recentResults.count) consecutive failures", toolId: "StabilityRegulator")
            return .noProgress(iterations: recentResults.count)
        }

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

        if tailCount >= 4 {
            let n = tailCount
            if tail[n - 4] == tail[n - 2] && tail[n - 3] == tail[n - 1] && tail[n - 4] != tail[n - 3] {
                return true
            }
        }

        if tailCount >= 6 {
            if tail[0] == tail[3] && tail[1] == tail[4] && tail[2] == tail[5] {
                return true
            }
        }

        return false
    }

    public func reset() {
        executionHistory.removeAll()
    }
}
