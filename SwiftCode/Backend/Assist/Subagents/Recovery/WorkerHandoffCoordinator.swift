import Foundation
import os

/// Manages Worker stop actions, handoffs, and reassignment (M-HANDOFF).
/// Fulfills SO5 and F-STOP: reason required, preserve vs hand off mode, remainder continuity.
@MainActor
public final class WorkerHandoffCoordinator: Sendable {
    public static let shared = WorkerHandoffCoordinator()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerHandoffCoordinator")

    private init() {}

    /// Executes stopping a Worker with mandatory non-empty reason and selected handoff mode
    public func executeStop(
        workerID: UUID,
        reason: String,
        mode: WorkerHandoffMode
    ) -> (handoff: WorkerHandoff, replacementWorker: Worker?)? {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            logger.error("Stop execution failed: Reason is mandatory.")
            return nil
        }

        guard let handoff = WorkerRuntimeState.shared.stopWorker(id: workerID, reason: trimmedReason, mode: mode) else {
            return nil
        }

        var replacementWorker: Worker? = nil

        if mode == .handoffToNewWorker {
            // Synthesize replacement worker with only remaining work and completed work context (INV-10)
            let replacementName = "\(handoff.originalWorkerName) (Continuation)"
            let replacementTask = "Continue remaining scope for: \(handoff.remainingTask). Completed work summary: \(handoff.completedWork.joined(separator: ", "))"

            var newWorker = Worker(
                name: replacementName,
                role: "Continuation Specialist",
                scope: handoff.remainingScope,
                task: String(replacementTask.prefix(500)),
                status: .queued,
                parentTaskID: handoff.parentTaskID
            )

            // Copy over files already changed and tests passed so work is never redone
            newWorker.recap = handoff.completedWork

            WorkerRuntimeState.shared.register(worker: newWorker)
            replacementWorker = newWorker

            // Update handoff record with replacement ID for lineage traceability
            var updatedHandoff = handoff
            updatedHandoff.replacementWorkerID = newWorker.id
            if let idx = WorkerRuntimeState.shared.handoffs.firstIndex(where: { $0.id == handoff.id }) {
                WorkerRuntimeState.shared.handoffs[idx] = updatedHandoff
            }

            logger.info("Created replacement worker '\(replacementName)' [ID: \(newWorker.id)] to continue remaining work.")
        }

        return (handoff, replacementWorker)
    }

    @discardableResult
    public func stopWorker(
        workerID: UUID,
        mode: WorkerHandoffMode,
        reason: String
    ) -> (handoff: WorkerHandoff, replacementWorker: Worker?)? {
        executeStop(workerID: workerID, reason: reason, mode: mode)
    }
}
