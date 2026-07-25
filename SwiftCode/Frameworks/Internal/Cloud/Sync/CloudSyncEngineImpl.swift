import Foundation

public final class CloudSyncEngineImpl: CloudSyncEngine, @unchecked Sendable {
    public static let shared = CloudSyncEngineImpl()

    public var syncState: SyncState = .idle
    public var lastSyncTime: Date? = nil
    public var syncProgress: Double = 0.0

    private var syncTimer: Timer?
    private var isRunning: Bool = false

    private init() {
        // Load last sync time
        if let timeVal = UserDefaults.standard.object(forKey: "com.swiftcode.cloud.sync.last_sync_time") as? Date {
            self.lastSyncTime = timeVal
        }
    }

    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        syncState = .idle

        // Setup automatic periodic background synchronization
        DispatchQueue.main.async {
            self.syncTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                Task {
                    try? await self?.triggerSync()
                }
            }
        }
    }

    public func pause() async {
        syncState = .paused
    }

    public func resume() async {
        syncState = .idle
        try? await triggerSync()
    }

    public func triggerSync() async throws {
        guard syncState != .paused else { return }
        guard syncState != .syncing else { return }

        syncState = .syncing
        syncProgress = 0.1

        do {
            // 1. Process local changes in UploadQueue
            let pendingUploads = await UploadQueue.shared.getPending()
            if !pendingUploads.isEmpty {
                let payloads = pendingUploads.map { $0.payload }
                // Push payloads to active provider (simulated integration)
                try await Task.sleep(nanoseconds: 300_000_000)

                for op in pendingUploads {
                    await UploadQueue.shared.remove(op.id)
                }
            }

            syncProgress = 0.6

            // 2. Fetch remote changes from active provider (delta sync)
            try await Task.sleep(nanoseconds: 200_000_000)

            syncProgress = 1.0
            syncState = .idle
            lastSyncTime = Date()
            UserDefaults.standard.set(lastSyncTime, forKey: "com.swiftcode.cloud.sync.last_sync_time")
        } catch {
            syncState = .error
            syncProgress = 0.0
            throw error
        }
    }
}
