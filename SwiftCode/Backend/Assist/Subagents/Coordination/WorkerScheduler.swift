import Foundation
import os

/// Schedules and coordinates live Worker execution with dependency resolution, concurrency control, and file ownership.
@MainActor
public final class WorkerScheduler: Sendable {
    public static let shared = WorkerScheduler()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerScheduler")
    private let engine = WorkerEngine()
    private var activeExecutionTasks: [UUID: Task<WorkerResult, Never>] = [:]

    private init() {}

    /// Schedules and executes a set of Worker assignments under parent Assist coordination.
    public func scheduleAndExecute(
        assignments: [WorkerAssignment],
        parentTaskID: UUID,
        context: AssistContext
    ) async -> [WorkerResult] {
        logger.info("Scheduling \(assignments.count) assignments for parent task \(parentTaskID)...")

        // 1. Create and register all Worker entities in WorkerRuntimeState
        var createdWorkers: [Worker] = []
        var nameToID: [String: UUID] = [:]

        for assignment in assignments {
            let model = WorkerModelSelector.shared.resolveModel(
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
        context: AssistContext,
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
        let review = await WorkerReviewEngine.shared.review(result: result, worker: worker)
        WorkerRuntimeState.shared.recordReview(id: worker.id, review: review)

        if review.status == .accepted {
            WorkerRuntimeState.shared.transitionWorker(
                id: worker.id,
                to: .completed,
                reason: "Worker output passed parent review and accepted."
            )
        } else {
            self.logger.warning("Worker '\(worker.name)' review status: \(review.status.rawValue)")

            // Attempt recovery for repair-required workers
            if review.status == .repairRequired {
                let recoveryError = WorkerError(
                    code: "REVIEW_REPAIR_REQUIRED",
                    message: review.issues.joined(separator: "; "),
                    timestamp: Date()
                )
                let recovered = await WorkerRecoveryEngine.shared.attemptRecovery(
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
            }
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
