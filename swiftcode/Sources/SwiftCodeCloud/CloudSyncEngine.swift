import Foundation

public actor CloudSyncEngine {
    public static let shared = CloudSyncEngine()

    private var provider: (any CloudProvider)?
    private var isSyncEnabled = false
    private var isSyncing = false
    private var statistics = CloudStatistics()
    private var pendingPayloads: [SyncPayload] = []
    private var syncTask: Task<Void, Never>?

    public private(set) var authManager: CloudAuthManager?

    private init() {
        self.authManager = nil
        self.isSyncEnabled = UserDefaults.standard.bool(
            forKey: CloudManager.syncEnabledKey
        )
        setupAutoSync()
    }

    public func configure(authManager: CloudAuthManager) {
        self.authManager = authManager
    }

    public init(testAuthManager: CloudAuthManager) {
        self.authManager = testAuthManager
        self.isSyncEnabled = false
    }

    public func setProvider(_ provider: any CloudProvider) {
        self.provider = provider
    }

    public func clearProvider() {
        provider = nil
    }

    public func hasProvider() -> Bool {
        provider != nil
    }

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

    public func addPendingPayload(_ payload: SyncPayload) {
        pendingPayloads.append(payload)
        statistics.pendingUploadsCount = pendingPayloads.count
        triggerSync()
    }

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
                guard
                    let authManager = authManager,
                    await authManager.isAuthenticated,
                    let swiftCodeID = await authManager.swiftCodeID
                else {
                    return
                }

                if !pendingPayloads.isEmpty {
                    let uploads = pendingPayloads

                    try await activeProvider.sync.pushDeltas(uploads)

                    pendingPayloads.removeAll {
                        uploads.contains($0)
                    }

                    statistics.totalUploadCount += uploads.count
                    statistics.pendingUploadsCount = pendingPayloads.count
                }

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

    public func cancelSync() {
        syncTask?.cancel()
        syncTask = nil

        isSyncing = false
        statistics.isSyncing = false
    }

    private func handleInboundPayload(_ delta: SyncPayload) async {
        _ = delta
    }

    nonisolated private func setupAutoSync() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                await CloudSyncEngine.shared.triggerSync()
            }
        }
    }
}
