import Foundation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.Cloud", category: "CloudManager")

@MainActor
@Observable
public final class CloudManager {
    public static let shared = CloudManager()

    public private(set) var isInitialized = false
    public private(set) var syncState: SyncState = .idle
    public private(set) var lastSyncTime: Date?
    public private(set) var currentError: String?
    public private(set) var isSyncEnabled = false

    private let engine = SyncEngine.shared
    private let cache = LocalCloudCache.shared

    private init() {
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: "com.swiftcode.cloud.syncEnabled")
    }

    /// Initializes Cloud Services and performs an initial check of user state.
    public func initialize() async {
        guard !isInitialized else { return }
        logger.info("Initializing CloudManager...")

        if await AuthManager.shared.isAuthenticated {
            isInitialized = true
            logger.info("CloudManager successfully initialized.")
            if isSyncEnabled {
                await startSync()
            }
        } else {
            logger.warning("CloudManager: User is not authenticated. Postponing full initialization.")
        }
    }

    /// Triggers a live synchronization run.
    public func sync() async {
        guard await AuthManager.shared.isAuthenticated else {
            self.currentError = CloudError.unauthenticated.localizedDescription
            return
        }

        self.syncState = .syncing
        self.currentError = nil

        do {
            try await engine.syncAll()
            self.lastSyncTime = Date()
            self.syncState = .idle
        } catch {
            self.syncState = .error
            self.currentError = error.localizedDescription
            logger.error("CloudManager synchronization failed: \(error.localizedDescription)")
        }
    }

    /// Enables and starts continuous synchronization.
    public func startSync() async {
        self.isSyncEnabled = true
        UserDefaults.standard.set(true, forKey: "com.swiftcode.cloud.syncEnabled")
        await sync()
    }

    /// Disables and stops continuous synchronization.
    public func stopSync() {
        self.isSyncEnabled = false
        UserDefaults.standard.set(false, forKey: "com.swiftcode.cloud.syncEnabled")
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
        logger.info("CloudManager: Successfully cleared state and cached data on logout.")
    }
}
