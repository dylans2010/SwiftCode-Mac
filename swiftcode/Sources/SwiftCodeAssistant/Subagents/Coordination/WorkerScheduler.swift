import Foundation
import os

// MARK: - Review & recovery seams
//
// Legacy's scheduler called `WorkerReviewEngine.shared.review` and
// `WorkerRecoveryEngine.shared.attemptRecovery` (Subagents/Review/ and
// Subagents/Recovery/). Those engines are not in this target and are not
// part of the parallel Models/Persistence port, so the scheduler takes
// them as injected seams instead of referencing types that do not exist.
// The defaults below carry Legacy's exact review and recovery *logic* —
// they are real implementations, not stubs — under new names so the real
// `WorkerReviewEngine` / `WorkerRecoveryEngine` can land later and replace
// them without a rename collision. Swap the defaults for the real engines
// when those files are ported; the scheduler's call sites do not change.

/// Reviews a finished `WorkerResult` before the parent Assist accepts it.
@MainActor
public protocol WorkerReviewRunner: Sendable {
    func review(result: WorkerResult, worker: Worker) async -> WorkerReview
}

/// Legacy `WorkerReviewEngine.review` logic, verbatim: audits tests,
/// known issues, and files-modified-vs-scope, then derives confidence and
/// a repair assignment. Enforces SO6: a Worker's "Done" is never
/// automatically accepted.
@MainActor
public struct DefaultWorkerReviewRunner: WorkerReviewRunner, Sendable {
    public init() {}

    public func review(result: WorkerResult, worker: Worker) async -> WorkerReview {
        var strengths: [String] = []
        var issues: [String] = []
        var recommendedFixes: [String] = []

        // 1. Audit Tests & Verification
        if result.tests.allSatisfy({ $0.passed }) && !result.tests.isEmpty {
            strengths.append("All \(result.tests.count) test assertions passed successfully.")
        } else if result.tests.contains(where: { !$0.passed }) {
            issues.append("One or more validation tests failed.")
            recommendedFixes.append("Fix failing test assertions in \(worker.scope).")
        }

        // 2. Audit Known Issues
        if !result.knownIssues.isEmpty {
            for issue in result.knownIssues {
                issues.append("Unresolved issue: \(issue)")
                recommendedFixes.append("Remediate issue: \(issue)")
            }
        }

        // 3. Audit Files Modified vs Declared Scope
        if result.modifiedFiles.isEmpty && result.createdFiles.isEmpty && result.deletedFiles.isEmpty {
            issues.append("No files were modified or created for assigned task.")
            recommendedFixes.append("Re-execute mutation operations for \(worker.scope).")
        } else {
            strengths.append("Modified \(result.modifiedFiles.count) files and created \(result.createdFiles.count) files within scope.")
        }

        // 4. Calculate Confidence and Outcome
        let confidence: Double = issues.isEmpty ? 1.0 : max(0.2, 1.0 - (Double(issues.count) * 0.25))
        let status: WorkerReviewState = issues.isEmpty ? .accepted : .repairRequired

        var repairAssignment: WorkerAssignment? = nil
        if status == .repairRequired {
            repairAssignment = WorkerAssignment(
                name: "\(worker.name) (Repair)",
                scope: worker.scope,
                task: "Repair detected issues: " + issues.joined(separator: "; "),
                role: worker.role,
                dependencies: []
            )
        }

        return WorkerReview(
            workerID: worker.id,
            reviewerModel: "Parent Assist Orchestrator",
            timestamp: Date(),
            status: status,
            confidence: confidence,
            strengths: strengths,
            issues: issues,
            recommendedFixes: recommendedFixes,
            repairAssignment: repairAssignment
        )
    }
}

/// Attempts to recover a failed worker (model fallback, then strategy
/// adjustment), re-executing it through the engine.
@MainActor
public protocol WorkerRecoveryRunner: Sendable {
    func attemptRecovery(
        for worker: Worker,
        error: WorkerError,
        assignment: WorkerAssignment,
        context: WorkerExecutionContext
    ) async -> Bool
}

/// Legacy `WorkerRecoveryEngine.attemptRecovery` logic, verbatim: first try
/// a fallback model from `WorkerModelSelector`, then re-execute with a
/// strategy-adjusted assignment. Enforces partial-work guarantees
/// (INV-10): completed work is never discarded.
@MainActor
public struct DefaultWorkerRecoveryRunner: WorkerRecoveryRunner, Sendable {
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerRecoveryRunner")
    private let turnRunner: any WorkerTurnRunner

    public init(turnRunner: any WorkerTurnRunner = MetaAssistTurnRunner()) {
        self.turnRunner = turnRunner
    }

    public func attemptRecovery(
        for worker: Worker,
        error: WorkerError,
        assignment: WorkerAssignment,
        context: WorkerExecutionContext
    ) async -> Bool {
        logger.info("Attempting recovery for worker '\(worker.name)' (Error: \(error.code))...")

        // 1. Model Fallback if model failed
        if let fallbackModel = await WorkerModelSelector.shared.fallbackModel(for: worker.modelUsed) {
            logger.info("Switching worker '\(worker.name)' to fallback model: \(fallbackModel)")
            WorkerRuntimeState.shared.updateWorker(id: worker.id) { w in
                w.modelUsed = fallbackModel
                w.currentAction = "Recovered: Resuming with fallback model \(fallbackModel)"
            }
            WorkerRuntimeState.shared.transitionWorker(
                id: worker.id,
                to: .working,
                reason: "Recovered with fallback model: \(fallbackModel)"
            )

            let engine = WorkerEngine(turnRunner: turnRunner)
            let prompt = await WorkerContextBuilder.shared.buildWorkerPrompt(
                for: worker,
                assignment: assignment,
                context: context,
                dependencyResults: []
            )
            let result = await engine.execute(
                worker: worker,
                scopedPrompt: prompt,
                context: context,
                modelID: fallbackModel
            )

            if result.knownIssues.isEmpty && result.remainingWork.isEmpty {
                WorkerRuntimeState.shared.transitionWorker(
                    id: worker.id,
                    to: .completed,
                    reason: "Recovery succeeded with fallback model."
                )
                return true
            }

            WorkerRuntimeState.shared.transitionWorker(
                id: worker.id,
                to: .failed,
                reason: "Recovery with fallback model also failed."
            )
            return false
        }

        // 2. Strategy adjustment: re-execute with modified approach
        WorkerRuntimeState.shared.updateWorker(id: worker.id) { w in
            w.currentAction = "Adjusting strategy: Bypassing failing step and proceeding to verification."
        }
        WorkerRuntimeState.shared.transitionWorker(
            id: worker.id,
            to: .working,
            reason: "Strategy adjustment for recovery."
        )

        let engine = WorkerEngine(turnRunner: turnRunner)
        let adjustedTask = assignment.task + " (Recovery: bypass previous failure point)"
        let adjustedAssignment = WorkerAssignment(
            name: assignment.name,
            scope: assignment.scope,
            task: String(adjustedTask.prefix(500)),
            role: assignment.role,
            dependencies: assignment.dependencies,
            targetFiles: assignment.targetFiles,
            preferredModel: assignment.preferredModel
        )
        let prompt = await WorkerContextBuilder.shared.buildWorkerPrompt(
            for: worker,
            assignment: adjustedAssignment,
            context: context,
            dependencyResults: []
        )
        let result = await engine.execute(
            worker: worker,
            scopedPrompt: prompt,
            context: context,
            modelID: worker.modelUsed
        )

        if result.knownIssues.isEmpty && result.remainingWork.isEmpty {
            WorkerRuntimeState.shared.transitionWorker(
                id: worker.id,
                to: .completed,
                reason: "Recovery succeeded with strategy adjustment."
            )
            return true
        }

        WorkerRuntimeState.shared.transitionWorker(
            id: worker.id,
            to: .failed,
            reason: "Recovery failed after strategy adjustment."
        )
        return false
    }
}

// MARK: - Scheduler

/// Schedules and coordinates live Worker execution with dependency resolution, concurrency control, and file ownership.
@MainActor
public final class WorkerScheduler: Sendable {
    public static let shared = WorkerScheduler()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerScheduler")
    private let engine: WorkerEngine
    private let reviewRunner: any WorkerReviewRunner
    private let recoveryRunner: any WorkerRecoveryRunner
    private var activeExecutionTasks: [UUID: Task<WorkerResult, Never>] = [:]

    public init(
        turnRunner: any WorkerTurnRunner = MetaAssistTurnRunner(),
        reviewRunner: any WorkerReviewRunner = DefaultWorkerReviewRunner(),
        recoveryRunner: (any WorkerRecoveryRunner)? = nil
    ) {
        self.engine = WorkerEngine(turnRunner: turnRunner)
        self.reviewRunner = reviewRunner
        self.recoveryRunner = recoveryRunner ?? DefaultWorkerRecoveryRunner(turnRunner: turnRunner)
    }

    /// Schedules and executes a set of Worker assignments under parent Assist coordination.
    public func scheduleAndExecute(
        assignments: [WorkerAssignment],
        parentTaskID: UUID,
        context: WorkerExecutionContext
    ) async -> [WorkerResult] {
        logger.info("Scheduling \(assignments.count) assignments for parent task \(parentTaskID)...")

        // 1. Create and register all Worker entities in WorkerRuntimeState
        var createdWorkers: [Worker] = []
        var nameToID: [String: UUID] = [:]

        for assignment in assignments {
            let model = await WorkerModelSelector.shared.resolveModel(
                for: assignment.role,
                scope: assignment.scope,
                preferredModel: assignment.preferredModel
            )

            let worker = Worker(
                name: assignment.name,
                role: assignment.role,
                scope: assignment.scope,
                task: assignment.task,
                status: .created,
                parentTaskID: parentTaskID,
                modelUsed: model
            )

            nameToID[assignment.name] = worker.id
            createdWorkers.append(worker)
            WorkerRuntimeState.shared.register(worker: worker)
        }

        // 2. Wire dependencies between workers
        for (idx, assignment) in assignments.enumerated() {
            let depIDs = assignment.dependencies.compactMap { nameToID[$0] }
            createdWorkers[idx].dependencies = depIDs
            WorkerRuntimeState.shared.updateWorker(id: createdWorkers[idx].id) { w in
                w.dependencies = depIDs
                w.status = depIDs.isEmpty ? .queued : .standby
            }
        }

        // 3. Coordinate execution respecting dependencies and safety
        var completedResults: [WorkerResult] = []
        var remainingWorkerIDs = createdWorkers.map { $0.id }

        while !remainingWorkerIDs.isEmpty && !Task.isCancelled {
            // Find all workers whose dependencies are completed
            let completedIDs = Set(completedResults.map { $0.workerID })
            let readyWorkers = createdWorkers.filter { worker in
                remainingWorkerIDs.contains(worker.id) &&
                worker.dependencies.allSatisfy { completedIDs.contains($0) }
            }

            if readyWorkers.isEmpty {
                // Dependency deadlock or remaining workers are blocked/cancelled
                logger.warning("No more ready workers could be scheduled. Deadlock or cancellation occurred.")
                for remainingID in remainingWorkerIDs {
                    WorkerRuntimeState.shared.transitionWorker(
                        id: remainingID,
                        to: .cancelled,
                        reason: "Cancelled: Dependencies could not be resolved."
                    )
                }
                break
            }

            // Run ready workers concurrently using cooperative async Tasks
            let tasks = readyWorkers.map { worker -> Task<WorkerResult, Never> in
                let assignment = assignments.first(where: { $0.name == worker.name }) ?? WorkerAssignment(
                    name: worker.name,
                    scope: worker.scope,
                    task: worker.task,
                    role: worker.role
                )

                let task = Task { @MainActor in
                    await self.executeSingleWorker(
                        worker: worker,
                        assignment: assignment,
                        context: context,
                        dependencyResults: completedResults
                    )
                }
                activeExecutionTasks[worker.id] = task
                return task
            }

            var resultsChunk: [WorkerResult] = []
            for task in tasks {
                resultsChunk.append(await task.value)
            }
            for id in resultsChunk.map({ $0.workerID }) {
                activeExecutionTasks.removeValue(forKey: id)
            }

            completedResults.append(contentsOf: resultsChunk)
            let finishedIDs = Set(resultsChunk.map { $0.workerID })
            remainingWorkerIDs.removeAll(where: { finishedIDs.contains($0) })
        }

        logger.info("Scheduler completed execution of \(completedResults.count) workers.")
        return completedResults
    }

    private func executeSingleWorker(
        worker: Worker,
        assignment: WorkerAssignment,
        context: WorkerExecutionContext,
        dependencyResults: [WorkerResult]
    ) async -> WorkerResult {
        // Build isolated context
        let prompt = await WorkerContextBuilder.shared.buildWorkerPrompt(
            for: worker,
            assignment: assignment,
            context: context,
            dependencyResults: dependencyResults
        )

        // Execute worker
        let result = await self.engine.execute(
            worker: worker,
            scopedPrompt: prompt,
            context: context,
            modelID: worker.modelUsed
        )

        // Review result with parent review gate
        let review = await reviewRunner.review(result: result, worker: worker)
        WorkerRuntimeState.shared.recordReview(id: worker.id, review: review)

        if review.status == .accepted {
            WorkerRuntimeState.shared.transitionWorker(
                id: worker.id,
                to: .completed,
                reason: "Worker output passed parent review and accepted."
            )
        } else if review.status == .repairRequired {
            self.logger.warning("Worker '\(worker.name)' review requested repair: \(review.issues.joined(separator: "; "))")
            let recoveryError = WorkerError(
                code: "REVIEW_REPAIR_REQUIRED",
                message: review.issues.joined(separator: "; "),
                timestamp: Date()
            )
            let recovered = await recoveryRunner.attemptRecovery(
                for: worker,
                error: recoveryError,
                assignment: assignment,
                context: context
            )
            if !recovered {
                WorkerRuntimeState.shared.transitionWorker(
                    id: worker.id,
                    to: .failed,
                    reason: "Worker failed review and recovery was unsuccessful."
                )
            }
        } else {
            self.logger.warning("Worker '\(worker.name)' review status: \(review.status.rawValue) - transitioning to failed.")
            WorkerRuntimeState.shared.transitionWorker(
                id: worker.id,
                to: .failed,
                reason: "Worker review failed: \(review.issues.joined(separator: "; "))"
            )
        }

        return result
    }

    /// Cancels an active Worker with a mandatory non-empty reason
    public func cancelWorker(id: UUID, reason: String) {
        if let task = activeExecutionTasks[id] {
            task.cancel()
            activeExecutionTasks.removeValue(forKey: id)
        }
        _ = WorkerRuntimeState.shared.stopWorker(id: id, reason: reason, mode: .preserve)
    }
}

// MARK: - WorkerPersistenceStore seam

/// Backs `WorkerPersistenceStore`'s `WorkerScheduling` seam with the
/// real scheduler. Added by the migration coordinator during
/// cross-file verification. The resume path builds its execution
/// context from the parent task id and the real workspace root —
/// never a guessed root.
extension WorkerScheduler: WorkerScheduling {
    public func scheduleAndExecute(
        assignments: [WorkerAssignment],
        parentTaskID: UUID,
        workspaceRoot: URL
    ) async -> [WorkerResult] {
        await scheduleAndExecute(
            assignments: assignments,
            parentTaskID: parentTaskID,
            context: WorkerExecutionContext(sessionId: parentTaskID, workspaceRoot: workspaceRoot)
        )
    }
}
