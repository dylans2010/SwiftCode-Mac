import Foundation
import os

/// Self-healing and error recovery coordinator for Assist Workers (M-RECOVER).
/// Enforces partial work guarantees (INV-10): Completed work is never discarded.
@MainActor
public final class WorkerRecoveryEngine: Sendable {
    public static let shared = WorkerRecoveryEngine()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerRecoveryEngine")

    private init() {}

    /// Recovers a failed worker by re-executing with model fallback or strategy adjustment
    public func attemptRecovery(
        for worker: Worker,
        error: WorkerError,
        assignment: WorkerAssignment,
        context: AssistContext
    ) async -> Bool {
        logger.info("Attempting recovery for worker '\(worker.name)' (Error: \(error.code))...")

        // 1. Model Fallback if model failed
        if let fallbackModel = WorkerModelSelector.shared.fallbackModel(for: worker.modelUsed) {
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

            let engine = WorkerEngine()
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

        let engine = WorkerEngine()
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
