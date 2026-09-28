import Foundation
import os

/// Durable persistence and crash-recovery engine for Assist Workers (M-PERSIST).
/// Extends existing Assist persistence architecture to ensure no Worker work is ever lost (INV-10).
@MainActor
public final class WorkerPersistenceStore: Sendable {
    public static let shared = WorkerPersistenceStore()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerPersistenceStore")
    private let storageKey = "com.swiftcode.assist.workers.tree"

    public struct PersistedTaskTree: Codable {
        public let parentTaskID: UUID
        public let timestamp: Date
        public let workers: [Worker]
        public let handoffs: [WorkerHandoff]
    }

    private init() {}

    /// Persists the active Worker tree continuously to durable storage
    public func persistWorkers(_ workers: [Worker], parentTaskID: UUID) {
        let tree = PersistedTaskTree(
            parentTaskID: parentTaskID,
            timestamp: Date(),
            workers: workers,
            handoffs: WorkerRuntimeState.shared.handoffs
        )

        do {
            let data = try JSONEncoder().encode(tree)
            UserDefaults.standard.set(data, forKey: storageKey)
            logger.info("Durable snapshot of \(workers.count) workers persisted for task \(parentTaskID).")
        } catch {
            logger.error("Failed to encode Worker tree for persistence: \(error.localizedDescription)")
        }
    }

    /// Restores previously persisted Workers upon application restart or recovery
    public func restoreLastSession() -> PersistedTaskTree? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }

        do {
            let tree = try JSONDecoder().decode(PersistedTaskTree.self, from: data)
            logger.info("Restored persisted task tree with \(tree.workers.count) workers from \(tree.timestamp).")

            // Re-hydrate WorkerRuntimeState with recovered workers
            for worker in tree.workers {
                WorkerRuntimeState.shared.register(worker: worker)
            }
            WorkerRuntimeState.shared.handoffs = tree.handoffs

            return tree
        } catch {
            logger.error("Failed to decode persisted Worker tree: \(error.localizedDescription)")
            return nil
        }
    }

    /// Clears persisted records for a completed and cleanly archived task
    public func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
