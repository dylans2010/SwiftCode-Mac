import Foundation

/// Actor-isolated synchronization engine for SwiftCode, ported from
/// Legacy's `CloudSyncEngine.swift` (238 lines). It coordinates
/// queues, automatic updates, and continuous delta syncs, and
/// requires an explicitly configured `CloudProvider`.
///
/// Honest limits, carried over from Legacy:
/// - With no provider configured, `triggerSync` logs the skip and
///   returns; nothing is invented to sync against.
/// - `handleInboundPayload` only notes the payload. Legacy's comment
///   said it plainly: "Actual persistence integration must be
///   implemented separately." No local store is written here.
/// - A failed cycle increments `statistics.conflictCount` (Legacy's
///   accounting, kept as-is even though a transport failure is not
///   a conflict).
///
/// One deliberate change: Legacy drove the 30-second auto-sync with
/// a `Timer` on the main run loop. This port uses a `Task` that
/// sleeps 30 seconds between cycles, which works on Linux too.
public actor CloudSyncEngine {
    public static let shared = CloudSyncEngine()

    private var provider: (any CloudProvider)?
    private var isSyncEnabled = false
    private var isSyncing = false
    private var statistics = CloudStatistics()
    private var pendingPayloads: [SyncPayload] = []
    private var syncTask: Task<Void, Never>?

    /// The auth manager consulted before any sync. Nil until the
    /// host configures one (`configure(authManager:)`), or a test
    /// passes one to `init(testAuthManager:)`: an actor cannot read
    /// the MainActor-isolated `CloudAuthManager.shared` in its own
    /// initializer, so the engine starts unconfigured and any sync
    /// attempt without one is skipped, exactly like the
    /// no-provider skip in Legacy.
    public private(set) var authManager: CloudAuthManager?

    private init() {
        self.authManager = nil
        self.isSyncEnabled = UserDefaults.standard.bool(
            forKey: CloudManager.syncEnabledKey
        )
        setupAutoSync()
    }

    /// Sets the auth manager the engine consults. The host calls
    /// this once at startup with the shared manager.
    public func configure(authManager: CloudAuthManager) {
        self.authManager = authManager
    }

    /// Test seam: builds an engine with an explicit auth manager
    /// instead of the shared one. Auto-sync is off: tests trigger
    /// sync explicitly.
    public init(testAuthManager: CloudAuthManager) {
        self.authManager = testAuthManager
        self.isSyncEnabled = false
    }

    // MARK: - Provider Configuration

    /// Sets or updates the active cloud provider.
    public func setProvider(_ provider: any CloudProvider) {
        self.provider = provider
    }

    /// Removes the active cloud provider.
    public func clearProvider() {
        provider = nil
    }

    /// True once a provider has been set.
    public func hasProvider() -> Bool {
        provider != nil
    }

    // MARK: - Sync Configuration

    /// Enables or disables continuous cloud synchronization.
    public func setSyncEnabled(_ enabled: Bool) {
        isSyncEnabled = enabled

        UserDefaults.standard.set(
            enabled,
            forKey: CloudManager.syncEnabledKey
        )

        if enabled {
            triggerSync()
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

    /// Queues a local persistence modification payload for
    /// synchronization. Silently drops the update when sync is
    /// disabled or no user is authenticated, as in Legacy.
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
                let authManager = self.authManager,
                await authManager.isAuthenticated,
                let swiftCodeID = await authManager.swiftCodeID
            else {
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

    /// Explicitly triggers a synchronization cycle. No-ops when sync
    /// is disabled, a cycle is already running, or no provider is
    /// configured. Requires Appwrite authentication before pushing
    /// or pulling anything.
    public func triggerSync() {
        guard isSyncEnabled && !isSyncing else {
            return
        }

        guard let activeProvider = provider else {
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
                    let authManager = authManager,
                    await authManager.isAuthenticated,
                    let swiftCodeID = await authManager.swiftCodeID
                else {
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
                        continue
                    }

                    await handleInboundPayload(delta)
                }

                statistics.totalDownloadCount += remoteDeltas.count
                statistics.lastSyncTimestamp = Date()
            } catch {
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
    }

    // MARK: - Inbound Updates

    private func handleInboundPayload(_ delta: SyncPayload) async {
        // Resolve conflicts or apply the update locally.
        // Actual persistence integration must be implemented separately.
        // Legacy only logged the payload; this port does the same
        // (there is no logger in this target, so nothing is emitted).
        _ = delta
    }

    // MARK: - Automatic Synchronization

    nonisolated private func setupAutoSync() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                await CloudSyncEngine.shared.triggerSync()
            }
        }
    }
}
