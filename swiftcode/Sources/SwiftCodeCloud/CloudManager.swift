import Foundation

@MainActor
public final class CloudManager {
    public static let shared = CloudManager()

    public private(set) var isInitialized = false
    public private(set) var syncState: SyncState = .idle
    public private(set) var lastSyncTime: Date?
    public private(set) var currentError: String?
    public private(set) var isSyncEnabled = false

    private let authManager: CloudAuthManager
    private let cache: LocalCloudCache

    public init(authManager: CloudAuthManager = CloudAuthManager.shared, cache: LocalCloudCache = LocalCloudCache.shared) {
        self.authManager = authManager
        self.cache = cache
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
    }

    public nonisolated static let syncEnabledKey = "com.swiftcode.cloud.syncEnabled"

    public func initialize() async {
        guard !isInitialized else { return }
        if authManager.isAuthenticated {
            isInitialized = true
            if isSyncEnabled {
                await startSync()
            }
        }
    }

    public func sync() async {
        guard authManager.isAuthenticated else {
            self.currentError = CloudError.unauthenticated.localizedDescription
            return
        }

        self.syncState = .syncing
        self.currentError = nil
        self.lastSyncTime = Date()
        self.syncState = .idle
    }

    public func startSync() async {
        self.isSyncEnabled = true
        UserDefaults.standard.set(true, forKey: Self.syncEnabledKey)
        await sync()
    }

    public func stopSync() {
        self.isSyncEnabled = false
        UserDefaults.standard.set(false, forKey: Self.syncEnabledKey)
        self.syncState = .paused
    }

    public func handleLogout() async {
        stopSync()
        await cache.clear()
        self.lastSyncTime = nil
        self.currentError = nil
        self.syncState = .idle
        self.isInitialized = false
    }
}
