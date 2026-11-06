import Foundation

/// Orchestrates cloud services, ported from Legacy's
/// `CloudManager.swift` (84 lines) with Legacy's exact semantics:
///
/// - `initialize()` does nothing until the user is authenticated,
///   then marks itself initialized and starts syncing when sync is
///   enabled.
/// - `sync()` is effectively a no-op: it refuses when unauthenticated
///   and otherwise only stamps `lastSyncTime` and returns to idle.
///   Legacy never synced a record here — there is no record syncing
///   to port, and none is invented. (The one change: Legacy wrapped
///   the stamp in a `do`/`catch` that could never throw; the dead
///   `catch` is dropped.)
/// - `startSync` / `stopSync` flip the persisted
///   `com.swiftcode.cloud.syncEnabled` flag; `stopSync` leaves the
///   state `.paused`.
/// - `handleLogout` stops sync, clears the local cache, and resets
///   all state.
///
/// Legacy read the shared `AuthManager` directly; this manager takes
/// a `CloudAuthManager` (defaulting to the shared one) so tests can
/// substitute one backed by a stub transport.
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

    /// The `UserDefaults` key for the sync-enabled flag, shared with
    /// `CloudSyncEngine` and Legacy's `CloudManagementView`
    /// (`@AppStorage("com.swiftcode.cloud.syncEnabled")`).
    public nonisolated static let syncEnabledKey = "com.swiftcode.cloud.syncEnabled"

    /// Initializes Cloud Services and performs an initial check of
    /// user state.
    public func initialize() async {
        guard !isInitialized else { return }
        if authManager.isAuthenticated {
            isInitialized = true
            if isSyncEnabled {
                await startSync()
            }
        }
        // Unauthenticated: full initialization is postponed, as in
        // Legacy — nothing is marked initialized.
    }

    /// Triggers a live synchronization run. Honest no-op, as in
    /// Legacy: it refuses when unauthenticated and otherwise only
    /// stamps `lastSyncTime`. No record is read from or written to
    /// any remote.
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

    /// Enables and starts continuous synchronization.
    public func startSync() async {
        self.isSyncEnabled = true
        UserDefaults.standard.set(true, forKey: Self.syncEnabledKey)
        await sync()
    }

    /// Disables and stops continuous synchronization.
    public func stopSync() {
        self.isSyncEnabled = false
        UserDefaults.standard.set(false, forKey: Self.syncEnabledKey)
        self.syncState = .paused
    }

    /// Clears cached local data and resets state upon user logout.
    public func handleLogout() async {
        stopSync()
        await cache.clear()
        self.lastSyncTime = nil
        self.currentError = nil
        self.syncState = .idle
        self.isInitialized = false
    }
}
