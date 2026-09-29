import Foundation

/// Maintains the autonomous multi-goal graph across a takeover session.
/// Tracks root → current → completed → pending → rejected goal relationships.
@MainActor
public final class AssistGoalGraph {
    public private(set) var rootGoal: String = ""
    public private(set) var goals: [AssistGoal] = []
    public private(set) var currentGoalId: UUID?

    public var pendingGoals: [AssistGoal] { goals.filter { $0.status == .pending } }
    public var completedGoals: [AssistGoal] { goals.filter { $0.status == .completed } }
    public var rejectedGoals: [AssistGoal] { goals.filter { $0.status == .rejected } }
    public var totalGoalCount: Int { goals.count }
    public var maxDepth: Int { goals.map { $0.provenance.generationDepth }.max() ?? 0 }

    public func setRoot(_ title: String) {
        if rootGoal.isEmpty { rootGoal = title }
    }

    public func goal(withTitle title: String) -> AssistGoal? {
        let normalized = Self.normalize(title)
        return goals.first { Self.normalize($0.title) == normalized }
    }

    public func add(_ goal: AssistGoal) {
        goals.append(goal)
    }

    public func markInProgress(id: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].status = .inProgress
        goals[index].startedAt = Date()
        currentGoalId = id
    }

    public func markCompleted(id: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].status = .completed
        goals[index].completedAt = Date()
        if currentGoalId == id { currentGoalId = nil }
    }

    public func markRejected(id: UUID, reason: String) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].status = .rejected
        goals[index].executionResult = reason
    }

    private static func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Session-wide coordination state shared between the expansion, continuation,
/// drift, and stability engines so safety limits observe the whole takeover loop.
@MainActor
public final class AssistTakeoverSessionState {
    public static let shared = AssistTakeoverSessionState()

    public private(set) var consecutiveFailures = 0
    public private(set) var goalGraph = AssistGoalGraph()

    private init() {}

    public func recordSuccess() { consecutiveFailures = 0 }
    public func recordFailure() { consecutiveFailures += 1 }

    public func reset() {
        consecutiveFailures = 0
        goalGraph = AssistGoalGraph()
    }
}

/// Determines whether to continue autonomous execution and generates next tasks
@MainActor
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

        let session = AssistTakeoverSessionState.shared
        let graph = session.goalGraph

        if completedTaskCount >= 50 {
            await context.logger.info("Continuation halted: task count limit reached", toolId: "TaskContinuation")
            return false
        }

        if graph.totalGoalCount >= AssistGoalSafeguards.maxTotalExpandedGoals {
            await context.logger.info("Continuation halted: total goal limit reached", toolId: "TaskContinuation")
            return false
        }

        if graph.maxDepth >= AssistGoalSafeguards.maxDepth {
            await context.logger.info("Continuation halted: max goal depth reached", toolId: "TaskContinuation")
            return false
        }

        if session.consecutiveFailures >= AssistGoalSafeguards.maxConsecutiveFailures {
            await context.logger.info("Continuation halted: consecutive failure circuit breaker", toolId: "TaskContinuation")
            return false
        }

        guard !graph.pendingGoals.isEmpty else {
            await context.logger.info("No pending goals, ending autonomous execution", toolId: "TaskContinuation")
            return false
        }

        return true
    }

    /// Generates the next task to execute, validating each candidate against the goal graph
    public func generateNextTask(previousGoal: String, completedPlan: AssistExecutionPlan, expandedGoals: [String]) async -> String? {
        let session = AssistTakeoverSessionState.shared
        let rootGoal = session.goalGraph.rootGoal.isEmpty ? previousGoal : session.goalGraph.rootGoal

        for title in expandedGoals {
            guard let goal = session.goalGraph.goal(withTitle: title), goal.status == .pending else { continue }

            let validation = AssistGoalSafeguards.validateCandidate(
                candidateTitle: goal.title,
                candidateObjective: goal.detailedObjective,
                existingGoals: session.goalGraph.goals,
                rootGoal: rootGoal,
                depth: goal.provenance.generationDepth,
                consecutiveFailures: session.consecutiveFailures
            )

            if validation.isValid {
                session.goalGraph.markInProgress(id: goal.id)
                await context.logger.info("Next autonomous task: \(title)", toolId: "TaskContinuation")
                return title
            }

            session.goalGraph.markRejected(id: goal.id, reason: validation.rejectionReason ?? "Failed validation")
            await context.logger.info("Rejected continuation goal '\(title)': \(validation.rejectionReason ?? "unknown")", toolId: "TaskContinuation")
        }

        await context.logger.info("No expanded goals available, ending autonomous execution", toolId: "TaskContinuation")
        return nil
    }

    /// Resets the continuation state
    public func reset() {
        completedTaskCount = 0
        AssistTakeoverSessionState.shared.reset()
    }
}
