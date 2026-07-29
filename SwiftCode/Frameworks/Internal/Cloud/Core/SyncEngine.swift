import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Cloud", category: "SyncEngine")

public actor SyncEngine {
    public static let shared = SyncEngine()

    private var isSyncing = false
    private let provider = SupabaseProvider.shared
    private let cache = LocalCloudCache.shared
    private let queue = SyncQueue.shared
    private let resolver = ConflictResolver.shared

    private init() {}

    /// Main synchronization method: pulls remote changes and resolves conflicts.
    public func syncAll() async throws {
        guard !isSyncing else {
            logger.info("Synchronization is already in progress.")
            return
        }

        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw CloudError.unauthenticated
        }

        isSyncing = true
        logger.info("Starting synchronization process for \(swiftCodeID, privacy: .public)...")

        defer {
            isSyncing = false
        }

        // 1. Process outbound queue
        let operations = await queue.getAll()
        for op in operations {
            if op.type == .upload {
                do {
                    if let cached = await cache.getRecord(recordType: "editor_settings", key: op.recordID) {
                        try await provider.saveRecord(cached)
                        await queue.removeOperation(id: op.id)
                    }
                } catch {
                    var mutableOp = op
                    mutableOp.retryCount += 1
                    mutableOp.errorState = error.localizedDescription
                    await queue.updateOperation(mutableOp)
                    logger.error("Failed to upload record \(op.recordID): \(error.localizedDescription)")
                }
            }
        }

        // 2. Fetch and merge editor_settings
        do {
            let remoteRecords = try await provider.fetchRecords(recordType: "editor_settings")
            for remote in remoteRecords {
                if let local = await cache.getRecord(recordType: remote.recordType, key: remote.recordKey) {
                    if local != remote {
                        // Conflict detected!
                        let resolved = resolver.resolve(local: local, remote: remote)
                        await cache.saveRecord(resolved)
                        if resolved == local {
                            // Local won, upload local to remote
                            try? await provider.saveRecord(resolved)
                        }
                    }
                } else {
                    // No local record found, save remote directly to local cache
                    await cache.saveRecord(remote)
                }
            }
        } catch {
            logger.error("Failed to sync editor_settings: \(error.localizedDescription)")
            throw CloudError.syncFailed(error.localizedDescription)
        }

        logger.info("Cloud synchronization completed successfully.")
    }
}
