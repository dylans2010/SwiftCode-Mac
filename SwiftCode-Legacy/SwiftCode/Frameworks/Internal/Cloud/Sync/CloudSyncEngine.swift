import Foundation
import os

private let logger = Logger(
    subsystem: "com.swiftcode.Cloud",
    category: "CloudSyncEngine"
)

/// Actor-isolated synchronization engine for SwiftCode.
/// Coordinates queues, heartbeats, automatic updates, and continuous delta syncs.
/// Requires an explicitly configured CloudProvider.
public actor CloudSyncEngine {
    public static let shared = CloudSyncEngine()

    private var provider: CloudProvider?
    private var isSyncEnabled = false
    private var isSyncing = false
    private var statistics = CloudStatistics()
    private var pendingPayloads: [SyncPayload] = []
    private var syncTask: Task<Void, Never>?

    private init() {
        self.isSyncEnabled = UserDefaults.standard.bool(
            forKey: "com.swiftcode.cloud.syncEnabled"
        )

        setupAutoSync()
    }

    // MARK: - Provider Configuration

    /// Sets or updates the active cloud provider.
    public func setProvider(_ provider: CloudProvider) {
        self.provider = provider
        logger.info("CloudSyncEngine active provider initialized successfully.")
    }

    /// Removes the active cloud provider.
    public func clearProvider() {
        provider = nil
        logger.info("CloudSyncEngine provider cleared.")
    }

    // MARK: - Sync Configuration

    /// Enables or disables continuous cloud synchronization.
    public func setSyncEnabled(_ enabled: Bool) {
        isSyncEnabled = enabled

        UserDefaults.standard.set(
            enabled,
            forKey: "com.swiftcode.cloud.syncEnabled"
        )

        if enabled {
            logger.info(
                "CloudSyncEngine enabled. Starting background delta sync cycles."
            )
            triggerSync()
        } else {
            logger.info(
                "CloudSyncEngine disabled. Pausing background delta sync cycles."
            )
        }
    }

    public func getStatistics() -> CloudStatistics {
        return statistics
    }

    // MARK: - Pending Payloads

    /// Appends a payload to the pending outbound updates list.
    public func addPendingPayload(_ payload: SyncPayload) {
        pendingPayloads.append(payload)
        statistics.pendingUploadsCount = pendingPayloads.count
        triggerSync()
    }

    /// Queues a local persistence modification payload for synchronization.
    public func queueLocalUpdate(
        tableName: String,
        recordID: String,
        payload: [String: String],
        isDeleted: Bool = false
    ) {
        guard isSyncEnabled else {
            return
        }

        Task {
            guard
                await AuthManager.shared.isAuthenticated,
                let swiftCodeID = await AuthManager.shared.swiftCodeID
            else {
                logger.warning(
                    "CloudSyncEngine: Skipped queuing update. No authenticated Appwrite user."
                )
                return
            }

            let syncPayload = SyncPayload(
                recordID: recordID,
                tableName: tableName,
                userID: swiftCodeID,
                payload: payload,
                version: 1,
                clientUpdatedAt: Date(),
                isDeleted: isDeleted
            )

            await self.addPendingPayload(syncPayload)
        }
    }

    // MARK: - Synchronization

    /// Explicitly triggers a synchronization cycle.
    public func triggerSync() {
        guard isSyncEnabled && !isSyncing else {
            return
        }

        guard let activeProvider = provider else {
            logger.warning(
                "CloudSyncEngine: Sync skipped because no cloud provider is configured."
            )
            return
        }

        isSyncing = true
        statistics.isSyncing = true

        syncTask = Task {
            defer {
                isSyncing = false
                statistics.isSyncing = false
            }

            do {
                // Require Appwrite authentication before synchronizing.
                guard
                    await AuthManager.shared.isAuthenticated,
                    let swiftCodeID = await AuthManager.shared.swiftCodeID
                else {
                    logger.warning(
                        "CloudSyncEngine: Sync aborted. Appwrite authentication is required."
                    )
                    return
                }

                // Process outbound pending updates.
                if !pendingPayloads.isEmpty {
                    let uploads = pendingPayloads

                    try await activeProvider.sync.pushDeltas(uploads)

                    pendingPayloads.removeAll {
                        uploads.contains($0)
                    }

                    statistics.totalUploadCount += uploads.count
                    statistics.pendingUploadsCount = pendingPayloads.count
                }

                // Pull inbound updates.
                let lastSync = statistics.lastSyncTimestamp
                    ?? Date().addingTimeInterval(-86_400)

                let remoteDeltas = try await activeProvider.sync.pullDeltas(
                    since: lastSync,
                    tableName: "projects"
                )

                for delta in remoteDeltas {
                    guard delta.userID == swiftCodeID else {
                        logger.warning(
                            "CloudSyncEngine: Ignored a delta belonging to another user."
                        )
                        continue
                    }

                    await handleInboundPayload(delta)
                }

                statistics.totalDownloadCount += remoteDeltas.count
                statistics.lastSyncTimestamp = Date()

                logger.info(
                    "CloudSyncEngine synchronization cycle completed successfully."
                )
            } catch {
                logger.error(
                    "CloudSyncEngine sync cycle failed: \(error.localizedDescription)"
                )
                statistics.conflictCount += 1
            }
        }
    }

    /// Cancels the currently running synchronization task.
    public func cancelSync() {
        syncTask?.cancel()
        syncTask = nil

        isSyncing = false
        statistics.isSyncing = false

        logger.info(
            "CloudSyncEngine: Current synchronization run canceled by client."
        )
    }

    // MARK: - Inbound Updates

    private func handleInboundPayload(_ delta: SyncPayload) async {
        // Resolve conflicts or apply the update locally.
        // Actual persistence integration must be implemented separately.
        logger.info(
            "Handling inbound sync payload for \(delta.tableName): \(delta.recordID)"
        )
    }

    // MARK: - Automatic Synchronization

    nonisolated private func setupAutoSync() {
        DispatchQueue.main.async {
            Timer.scheduledTimer(
                withTimeInterval: 30,
                repeats: true
            ) { _ in
                Task {
                    await CloudSyncEngine.shared.triggerSync()
                }
            }
        }
    }
}
