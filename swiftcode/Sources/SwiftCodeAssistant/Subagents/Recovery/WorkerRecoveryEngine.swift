import Foundation
import os

// Ported from Legacy:
//   SwiftCode/Backend/Assist/Subagents/Recovery/WorkerRecoveryEngine.swift
// Direct port of Legacy behaviour (Dylan's own code, authorised for porting
// under MIT). Depends on types ported in parallel into SwiftCodeAssistant:
// Worker, WorkerError, WorkerAssignment, WorkerResult, WorkerRuntimeState,
// WorkerModelSelector (Models), WorkerEngine and WorkerExecutionContext
// (Engine), WorkerContextBuilder (Context), and
// WorkerPersistenceStore + WorkerReconciliationReport (Persistence).
// Declares no model types itself.
//
// `recoverFromDisk` is the crash-recovery entry point for this coordinator:
// it delegates to WorkerPersistenceStore.restoreReconcileAndResume, the real
// Legacy implementation that restores the persisted worker tree from disk,
// reconciles claimed file changes against the filesystem, and resumes
// interrupted workers — it never fabricates a recovered result.
//
// Coordinator fix (cross-file verification): Legacy's `AssistContext`
// does not exist in the destination, so both methods take the
// destination's narrow `WorkerExecutionContext` instead; the
// persistence store has no `.shared` singleton, so the engine holds
// an injected store backed by the real shared runtime state and
// scheduler (see the `WorkerRuntimeStateProviding` / `WorkerScheduling`
// conformances).

/// Self-healing and error recovery coordinator for Assist Workers (M-RECOVER).
/// Enforces partial work guarantees (INV-10): Completed work is never discarded.
@MainActor
public final class WorkerRecoveryEngine: Sendable {
    public static let shared = WorkerRecoveryEngine()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerRecoveryEngine")
    private let store: WorkerPersistenceStore

    public init(store: WorkerPersistenceStore? = nil) {
        self.store = store ?? WorkerPersistenceStore(
            runtimeState: WorkerRuntimeState.shared,
            scheduler: WorkerScheduler.shared
        )
    }

    /// Full crash-recovery entry point: rebuild worker state from the
    /// persistence store on disk, reconcile claimed vs actual file changes,
    /// and resume interrupted workers (or leave them failed, honestly).
    ///
    /// Returns the restored tree (nil when nothing was persisted), the
    /// reconciliation report (discrepancies = claimed changes the filesystem
    /// does not bear out), and the real results of any resumed workers.
    /// A worker whose claimed files do not exist is reported as a
    /// discrepancy, never silently treated as recovered.
    public func recoverFromDisk(
        parentTaskID: UUID,
        workspaceRoot: URL
    ) async -> (
        tree: WorkerPersistenceStore.PersistedTaskTree?,
        report: WorkerReconciliationReport,
        results: [WorkerResult]
    ) {
        let outcome = await store.restoreReconcileAndResume(
            parentTaskID: parentTaskID,
            workspaceRoot: workspaceRoot
        )

        if outcome.report.discrepancies.isEmpty {
            logger.info("Crash recovery complete: \(outcome.report.summary) Resumed \(outcome.results.count) worker(s).")
        } else {
            logger.error("Crash recovery found \(outcome.report.discrepancies.count) file-claim discrepanc\(outcome.report.discrepancies.count == 1 ? "y" : "ies"): \(outcome.report.summary)")
            for discrepancy in outcome.report.discrepancies {
                logger.error("Discrepancy: \(discrepancy.description)")
            }
        }

        return outcome
    }

    /// Recovers a failed worker by re-executing with model fallback or strategy adjustment
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
