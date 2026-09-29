import Foundation
import Observation
import os

/// The single authoritative shared runtime state for all Assist Workers.
/// Observed directly by `WorkersOnAssistView`, `WorkersInfoView`, and `WorkersMainView` per INV-12.
@Observable
@MainActor
public final class WorkerRuntimeState: Sendable {
    public static let shared = WorkerRuntimeState()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerRuntimeState")

    public var workers: [Worker] = []
    public var allWorkers: [Worker] {
        workers
    }
    public var handoffs: [WorkerHandoff] = []
    public var selectedWorkerID: UUID?

    // UI Navigation State
    public var isMainViewPresented: Bool = false
    public var isInfoViewPresented: Bool = false

    // State Aggregations (O(1) computed properties for high responsiveness at 1, 5, 10+ workers)
    public var activeWorkers: [Worker] {
        workers.filter { $0.status.isActive }
    }

    public var completedWorkers: [Worker] {
        workers.filter { $0.status == .completed }
    }

    public var failedWorkers: [Worker] {
        workers.filter { $0.status == .failed }
    }

    public var standbyWorkers: [Worker] {
        workers.filter { $0.status == .standby }
    }

    public var activeCount: Int {
        activeWorkers.count
    }

    public var totalCount: Int {
        workers.count
    }

    public var completedCount: Int {
        completedWorkers.count
    }

    public var hasActiveWorkers: Bool {
        !activeWorkers.isEmpty
    }

    public var selectedWorker: Worker? {
        guard let id = selectedWorkerID else { return nil }
        return workers.first(where: { $0.id == id })
    }

    public func getWorker(id: UUID) -> Worker? {
        workers.first(where: { $0.id == id })
    }

    private init() {
        // Wire into the event bus for real-time synchronization
        WorkerEventBus.shared.subscribe { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleIncomingEvent(event)
            }
        }
    }

    // MARK: - State Mutations

    public func register(worker: Worker) {
        if let idx = workers.firstIndex(where: { $0.id == worker.id }) {
            workers[idx] = worker
        } else {
            workers.append(worker)
        }

        let event = WorkerEvent(
            workerID: worker.id,
            type: .workerCreated,
            title: "Worker Created",
            details: "\(worker.name) initialized with role: \(worker.role)"
        )
        WorkerEventBus.shared.emit(event)
    }

    public func updateWorker(id: UUID, mutate: (inout Worker) -> Void) {
        guard let idx = workers.firstIndex(where: { $0.id == id }) else { return }
        var copy = workers[idx]
        copy.updatedAt = Date()
        mutate(&copy)
        workers[idx] = copy
    }

    public func transitionWorker(id: UUID, to status: WorkerStatus, reason: String) {
        guard let idx = workers.firstIndex(where: { $0.id == id }) else { return }
        let oldStatus = workers[idx].status
        guard oldStatus != status else { return }

        workers[idx].status = status
        workers[idx].updatedAt = Date()
        workers[idx].currentAction = reason

        if status == .working && workers[idx].startedAt == nil {
            workers[idx].startedAt = Date()
        } else if status.isTerminal && workers[idx].completedAt == nil {
            workers[idx].completedAt = Date()
        }

        logger.info("[Worker \(self.workers[idx].name)] State Transition: \(oldStatus.rawValue) -> \(status.rawValue) | \(reason)")

        let eventType: WorkerEventType
        switch status {
        case .queued: eventType = .workerQueued
        case .working: eventType = .workerStarted
        case .reviewing: eventType = .workerReviewStarted
        case .completed: eventType = .workerCompleted
        case .failed: eventType = .workerFailed
        case .cancelled: eventType = .workerCancelled
        case .standby: eventType = .workerStandby
        case .blocked: eventType = .workerBlocked
        default: eventType = .workerProgressUpdated
        }

        let event = WorkerEvent(
            workerID: id,
            type: eventType,
            title: "Status: \(status.rawValue)",
            details: reason
        )
        WorkerEventBus.shared.emit(event)
    }

    public func updateProgress(id: UUID, progress: WorkerProgress) {
        guard let idx = workers.firstIndex(where: { $0.id == id }) else { return }
        workers[idx].progress = progress
        workers[idx].currentAction = progress.currentAction
        workers[idx].currentPhase = progress.phase
        workers[idx].updatedAt = Date()

        let event = WorkerEvent(
            workerID: id,
            type: .workerProgressUpdated,
            title: progress.phase.rawValue,
            details: progress.currentAction
        )
        WorkerEventBus.shared.emit(event)
    }

    public func recordFileChange(id: UUID, change: WorkerFileChange) {
        guard let idx = workers.firstIndex(where: { $0.id == id }) else { return }
        switch change.changeType {
        case .created:
            workers[idx].createdFiles.append(change)
        case .modified:
            if let existing = workers[idx].modifiedFiles.firstIndex(where: { $0.path == change.path }) {
                workers[idx].modifiedFiles[existing] = change
            } else {
                workers[idx].modifiedFiles.append(change)
            }
        case .deleted:
            workers[idx].deletedFiles.append(change)
        case .renamed:
            workers[idx].renamedFiles.append(change)
        }
        workers[idx].updatedAt = Date()

        let event = WorkerEvent(
            workerID: id,
            type: .workerFileChanged,
            title: "\(change.changeType.rawValue) \(change.filename)",
            details: change.path
        )
        WorkerEventBus.shared.emit(event)
    }

    public func recordTest(id: UUID, test: WorkerTestRecord) {
        guard let idx = workers.firstIndex(where: { $0.id == id }) else { return }
        workers[idx].testsRun.append(test)
        workers[idx].updatedAt = Date()

        let event = WorkerEvent(
            workerID: id,
            type: .workerTestCompleted,
            title: test.passed ? "Test Passed: \(test.testName)" : "Test Failed: \(test.testName)",
            details: test.failureReason ?? "Output length: \(test.output.count) chars"
        )
        WorkerEventBus.shared.emit(event)
    }

    public func recordReview(id: UUID, review: WorkerReview) {
        guard let idx = workers.firstIndex(where: { $0.id == id }) else { return }
        workers[idx].reviewState = review.status
        workers[idx].updatedAt = Date()

        let event = WorkerEvent(
            workerID: id,
            type: .workerReviewCompleted,
            title: "Review: \(review.status.rawValue)",
            details: "Confidence: \(Int(review.confidence * 100))% - Issues: \(review.issues.count)"
        )
        WorkerEventBus.shared.emit(event)
    }

    public func stopAllActiveWorkers(reason: String) {
        let active = workers.filter { !$0.status.isTerminal }
        for w in active {
            _ = stopWorker(id: w.id, reason: reason, mode: .preserve)
        }
    }

    public func clearAllWorkers() {
        workers.removeAll()
        handoffs.removeAll()
        selectedWorkerID = nil
    }

    public func stopWorker(id: UUID, reason: String, mode: WorkerHandoffMode) -> WorkerHandoff? {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("Stop Worker rejected: non-empty reason required")
            return nil
        }
        guard let idx = workers.firstIndex(where: { $0.id == id }) else { return nil }

        let worker = workers[idx]
        workers[idx].status = .cancelled
        workers[idx].cancellationReason = reason
        workers[idx].completedAt = Date()
        workers[idx].updatedAt = Date()

        let handoff = WorkerHandoff(
            originalWorkerID: worker.id,
            originalWorkerName: worker.name,
            parentTaskID: worker.parentTaskID,
            reason: reason,
            mode: mode,
            completedWork: worker.recap,
            remainingScope: worker.scope,
            remainingTask: worker.task,
            filesChanged: worker.allAffectedFiles,
            testsCompleted: worker.testsRun.filter { $0.passed }.map { $0.testName },
            knownProblems: worker.errorState != nil ? [worker.errorState!.message] : []
        )

        workers[idx].handoffState = handoff
        handoffs.append(handoff)

        let stopEvent = WorkerEvent(
            workerID: id,
            type: .workerCancelled,
            title: "Worker Stopped",
            details: "Reason: \(reason) | Mode: \(mode.rawValue)"
        )
        WorkerEventBus.shared.emit(stopEvent)

        let handoffEvent = WorkerEvent(
            workerID: id,
            type: .workerHandoffStarted,
            title: mode == .preserve ? "Work Preserved with Task" : "Handoff to Replacement Worker",
            details: reason
        )
        WorkerEventBus.shared.emit(handoffEvent)

        return handoff
    }

    public func clear() {
        workers.removeAll()
        handoffs.removeAll()
        selectedWorkerID = nil
    }

    // MARK: - Internal Event Listener

    private func handleIncomingEvent(_ event: WorkerEvent) {
        guard let idx = workers.firstIndex(where: { $0.id == event.workerID }) else { return }
        workers[idx].eventHistory.append(event)

        // Keep event history capped to prevent memory bloat on very long tasks
        if workers[idx].eventHistory.count > 100 {
            workers[idx].eventHistory.removeFirst(workers[idx].eventHistory.count - 100)
        }
    }
}
