import Foundation
import os

public struct WorkerReconciliationDiscrepancy: Identifiable, Codable, Sendable {
    public let id: UUID
    public let workerID: UUID
    public let workerName: String
    public let path: String
    public let claimedChange: FileChangeType
    public let actualState: String
    public let description: String

    public init(
        id: UUID = UUID(),
        workerID: UUID,
        workerName: String,
        path: String,
        claimedChange: FileChangeType,
        actualState: String,
        description: String
    ) {
        self.id = id
        self.workerID = workerID
        self.workerName = workerName
        self.path = path
        self.claimedChange = claimedChange
        self.actualState = actualState
        self.description = description
    }
}

public struct WorkerReconciliationReport: Codable, Sendable {
    public let timestamp: Date
    public let checkedWorkers: Int
    public let verifiedClaims: Int
    public let discrepancies: [WorkerReconciliationDiscrepancy]

    public var isClean: Bool {
        discrepancies.isEmpty
    }

    public var summary: String {
        if isClean {
            return "Reconciliation clean: \(verifiedClaims) file claims verified across \(checkedWorkers) workers."
        }
        return "Reconciliation found \(discrepancies.count) discrepanc\(discrepancies.count == 1 ? "y" : "ies") across \(checkedWorkers) workers (\(verifiedClaims) claims verified)."
    }
}

/// Durable persistence and crash-recovery engine for Assist Workers (M-PERSIST).
/// Extends existing Assist persistence architecture to ensure no Worker work is ever lost (INV-10).
@MainActor
public final class WorkerPersistenceStore: Sendable {
    public static let shared = WorkerPersistenceStore()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerPersistenceStore")
    private let storageKey = "com.swiftcode.assist.workers.tree"
    private let fileManager = FileManager.default
    private var recordedAssignments: [WorkerAssignment] = []

    public struct PersistedTaskTree: Codable {
        public let parentTaskID: UUID
        public let timestamp: Date
        public let workers: [Worker]
        public let assignments: [WorkerAssignment]
        public let handoffs: [WorkerHandoff]
        public let reviews: [WorkerReview]
        public let cancellations: [WorkerCancellation]
        public let dependencies: [WorkerDependency]
        public let events: [WorkerEvent]

        public init(
            parentTaskID: UUID,
            timestamp: Date,
            workers: [Worker],
            assignments: [WorkerAssignment] = [],
            handoffs: [WorkerHandoff] = [],
            reviews: [WorkerReview] = [],
            cancellations: [WorkerCancellation] = [],
            dependencies: [WorkerDependency] = [],
            events: [WorkerEvent] = []
        ) {
            self.parentTaskID = parentTaskID
            self.timestamp = timestamp
            self.workers = workers
            self.assignments = assignments
            self.handoffs = handoffs
            self.reviews = reviews
            self.cancellations = cancellations
            self.dependencies = dependencies
            self.events = events
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            parentTaskID = try container.decode(UUID.self, forKey: .parentTaskID)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            workers = try container.decode([Worker].self, forKey: .workers)
            assignments = try container.decodeIfPresent([WorkerAssignment].self, forKey: .assignments) ?? []
            handoffs = try container.decodeIfPresent([WorkerHandoff].self, forKey: .handoffs) ?? []
            reviews = try container.decodeIfPresent([WorkerReview].self, forKey: .reviews) ?? []
            cancellations = try container.decodeIfPresent([WorkerCancellation].self, forKey: .cancellations) ?? []
            dependencies = try container.decodeIfPresent([WorkerDependency].self, forKey: .dependencies) ?? []
            events = try container.decodeIfPresent([WorkerEvent].self, forKey: .events) ?? []
        }
    }

    private init() {}

    private func stateDirectory(in workspaceRoot: URL) -> URL {
        workspaceRoot.appendingPathComponent(".swiftcode/workers", isDirectory: true)
    }

    private func stateFileURL(in workspaceRoot: URL) -> URL {
        stateDirectory(in: workspaceRoot).appendingPathComponent("worker_state.json")
    }

    public func recordAssignments(_ assignments: [WorkerAssignment]) {
        for assignment in assignments {
            if let idx = recordedAssignments.firstIndex(where: { $0.name == assignment.name }) {
                recordedAssignments[idx] = assignment
            } else {
                recordedAssignments.append(assignment)
            }
        }
    }

    /// Persists the complete Worker tree continuously to durable storage
    public func persistWorkers(_ workers: [Worker], parentTaskID: UUID, workspaceRoot: URL? = nil) {
        let assignments = mergedAssignments(for: workers)
        let reviews = workers
            .filter { $0.reviewState != .notReviewed }
            .map { worker in
                WorkerReview(
                    workerID: worker.id,
                    reviewerModel: "Parent Assist Orchestrator",
                    status: worker.reviewState,
                    confidence: worker.reviewState == .accepted ? 1.0 : 0.5,
                    strengths: worker.recap,
                    issues: worker.result?.knownIssues ?? [],
                    recommendedFixes: worker.result?.remainingWork ?? []
                )
            }
        let cancellations = workers
            .compactMap { worker in
                worker.cancellationReason.map { reason in
                    WorkerCancellation(workerID: worker.id, reason: reason, workPreserved: worker.handoffState != nil)
                }
            }
        let dependencies = workers.flatMap { worker in
            worker.dependencies.map { depID in
                let satisfied = workers.first(where: { $0.id == depID })?.status == .completed
                return WorkerDependency(workerID: worker.id, dependsOnWorkerID: depID, isSatisfied: satisfied)
            }
        }
        let events = workers.flatMap { $0.eventHistory }.sorted { $0.timestamp < $1.timestamp }

        let tree = PersistedTaskTree(
            parentTaskID: parentTaskID,
            timestamp: Date(),
            workers: workers,
            assignments: assignments,
            handoffs: WorkerRuntimeState.shared.handoffs,
            reviews: reviews,
            cancellations: cancellations,
            dependencies: dependencies,
            events: events
        )

        do {
            let data = try JSONEncoder().encode(tree)
            UserDefaults.standard.set(data, forKey: storageKey)

            if let workspaceRoot = workspaceRoot {
                let directory = stateDirectory(in: workspaceRoot)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: stateFileURL(in: workspaceRoot), options: .atomic)
            }

            logger.info("Durable snapshot of \(workers.count) workers persisted for task \(parentTaskID).")
        } catch {
            logger.error("Failed to encode Worker tree for persistence: \(error.localizedDescription)")
        }
    }

    private func mergedAssignments(for workers: [Worker]) -> [WorkerAssignment] {
        var result = recordedAssignments
        let recordedNames = Set(result.map { $0.name })
        for worker in workers where !recordedNames.contains(worker.name) {
            let depNames = worker.dependencies.compactMap { depID in
                workers.first(where: { $0.id == depID })?.name
            }
            result.append(WorkerAssignment(
                name: worker.name,
                scope: worker.scope,
                task: worker.task,
                role: worker.role,
                dependencies: depNames
            ))
        }
        return result
    }

    /// Restores previously persisted Workers upon application restart or recovery
    public func restoreLastSession(from workspaceRoot: URL? = nil) -> PersistedTaskTree? {
        var tree = workspaceRoot != nil ? loadFromFile(in: workspaceRoot!) : nil
        if tree == nil {
            tree = loadFromUserDefaults()
        }

        guard let tree = tree else {
            return nil
        }

        logger.info("Restored persisted task tree with \(tree.workers.count) workers from \(tree.timestamp).")

        for worker in tree.workers {
            WorkerRuntimeState.shared.register(worker: worker)
        }
        WorkerRuntimeState.shared.handoffs = tree.handoffs

        return tree
    }

    private func loadFromFile(in workspaceRoot: URL) -> PersistedTaskTree? {
        let url = stateFileURL(in: workspaceRoot)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(PersistedTaskTree.self, from: data)
        } catch {
            logger.error("Failed to decode Worker tree from \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    private func loadFromUserDefaults() -> PersistedTaskTree? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(PersistedTaskTree.self, from: data)
        } catch {
            logger.error("Failed to decode persisted Worker tree: \(error.localizedDescription)")
            return nil
        }
    }

    /// Verifies claimed file changes against the actual filesystem after a session restore
    public func reconcileWithFilesystem(workspaceRoot: URL) -> WorkerReconciliationReport {
        var discrepancies: [WorkerReconciliationDiscrepancy] = []
        var verifiedClaims = 0
        let workers = WorkerRuntimeState.shared.allWorkers

        for worker in workers {
            for change in worker.fileChanges {
                let resolved = resolvePath(change.path, workspaceRoot: workspaceRoot)
                let exists = fileManager.fileExists(atPath: resolved)

                switch change.changeType {
                case .created, .modified, .renamed:
                    if exists {
                        verifiedClaims += 1
                    } else {
                        discrepancies.append(WorkerReconciliationDiscrepancy(
                            workerID: worker.id,
                            workerName: worker.name,
                            path: change.path,
                            claimedChange: change.changeType,
                            actualState: "missing",
                            description: "Worker '\(worker.name)' claimed \(change.changeType.rawValue.lowercased()) '\(change.path)' but the file does not exist on disk."
                        ))
                    }
                case .deleted:
                    if !exists {
                        verifiedClaims += 1
                    } else {
                        discrepancies.append(WorkerReconciliationDiscrepancy(
                            workerID: worker.id,
                            workerName: worker.name,
                            path: change.path,
                            claimedChange: .deleted,
                            actualState: "exists",
                            description: "Worker '\(worker.name)' claimed deleted '\(change.path)' but the file still exists on disk."
                        ))
                    }
                }
            }
        }

        return WorkerReconciliationReport(
            timestamp: Date(),
            checkedWorkers: workers.count,
            verifiedClaims: verifiedClaims,
            discrepancies: discrepancies
        )
    }

    private func resolvePath(_ path: String, workspaceRoot: URL) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return workspaceRoot.appendingPathComponent(path).path
    }

    /// Re-schedules workers that were interrupted mid-flight (non-terminal status at restore time)
    public func resumeInterruptedWorkers(context: AssistContext) async -> [WorkerResult] {
        let interrupted = WorkerRuntimeState.shared.allWorkers.filter { !$0.status.isTerminal }
        guard !interrupted.isEmpty else {
            return []
        }

        logger.info("Resuming \(interrupted.count) interrupted workers for session \(context.sessionId).")

        for worker in interrupted {
            WorkerRuntimeState.shared.stopWorker(
                id: worker.id,
                reason: "Session interrupted; remaining work resumed by replacement worker.",
                mode: .preserve
            )
        }

        let assignments = interrupted.map { worker in
            WorkerAssignment(
                name: worker.name,
                scope: worker.scope,
                task: worker.task,
                role: worker.role,
                dependencies: worker.dependencies.compactMap { depID in
                    WorkerRuntimeState.shared.getWorker(id: depID)?.name
                }
            )
        }

        return await WorkerScheduler.shared.scheduleAndExecute(
            assignments: assignments,
            parentTaskID: context.sessionId,
            context: context
        )
    }

    /// Full crash-recovery entry point: restore state, reconcile claims with disk, resume interrupted work
    public func restoreReconcileAndResume(context: AssistContext, workspaceRoot: URL) async -> (tree: PersistedTaskTree?, report: WorkerReconciliationReport, results: [WorkerResult]) {
        let tree = restoreLastSession(from: workspaceRoot)
        let report = reconcileWithFilesystem(workspaceRoot: workspaceRoot)
        let results = await resumeInterruptedWorkers(context: context)
        return (tree, report, results)
    }

    /// Clears persisted records for a completed and cleanly archived task
    public func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        recordedAssignments.removeAll()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SwiftCode/workers", isDirectory: true)
        if let directory = directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
