import Foundation
import os.log

public final class CloudSyncEngineImpl: CloudSyncEngine, @unchecked Sendable {
    public static let shared = CloudSyncEngineImpl()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "SyncEngine")

    public var syncState: SyncState = .idle
    public var lastSyncTime: Date? = nil
    public var syncProgress: Double = 0.0

    private var syncTimer: Timer?
    private var isRunning: Bool = false

    private init() {
        if let timeVal = UserDefaults.standard.object(forKey: "com.swiftcode.cloud.sync.last_sync_time") as? Date {
            self.lastSyncTime = timeVal
        }
    }

    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        syncState = .idle
        logger.info("CloudSyncEngine started.")

        // Background automatic periodic syncing every 60 seconds
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
        logger.info("CloudSyncEngine paused.")
    }

    public func resume() async {
        syncState = .idle
        logger.info("CloudSyncEngine resumed.")
        try? await triggerSync()
    }

    public func triggerSync() async throws {
        // Retrieve settings dynamically
        let syncEnabled = UserDefaults.standard.bool(forKey: "com.swiftcode.cloud.sync_enabled")
        guard syncEnabled else {
            logger.info("Sync skipped: Automated cloud syncing is disabled.")
            return
        }

        guard syncState != .paused else { return }
        guard syncState != .syncing else { return }

        logger.info("Sync triggered...")
        syncState = .syncing
        syncProgress = 0.1

        let rawProvider = UserDefaults.standard.string(forKey: "com.swiftcode.cloud.active_provider") ?? "None"
        let activeType = CloudProviderType(rawValue: rawProvider) ?? .none

        guard activeType != .none else {
            logger.info("Sync skipped: No preferred cloud provider selected.")
            syncState = .idle
            syncProgress = 0.0
            return
        }

        let provider: (any CloudProvider & SyncProvider)
        if activeType == .supabase {
            provider = SupabaseCloudProvider()
        } else {
            provider = ICloudCloudProvider()
        }

        do {
            // Verify active cloud connection
            let hasConnection = await provider.testConnection()
            guard hasConnection else {
                logger.warning("Sync paused: Active provider endpoint is offline.")
                syncState = .error
                syncProgress = 0.0
                return
            }

            syncProgress = 0.3

            // 1. PUSH local operations queued during offline state
            let pendingUploads = await UploadQueue.shared.getPending()
            if !pendingUploads.isEmpty {
                logger.info("Pushing \(pendingUploads.count) local updates to remote container...")
                let payloads = pendingUploads.map { $0.payload }
                let succeededIDs = try await provider.pushChanges(payloads)

                for op in pendingUploads {
                    if succeededIDs.contains(op.payload.resourceID) {
                        await UploadQueue.shared.remove(op.id)
                    } else {
                        // Increment retry counter and flag error
                        var updatedOp = op
                        updatedOp.retryCount += 1
                        updatedOp.lastAttempted = Date()
                        updatedOp.lastError = "Push rejected by provider."
                        await UploadQueue.shared.update(updatedOp)
                    }
                }
            }

            syncProgress = 0.6

            // 2. PULL remote updates since last successful sync anchor
            let pullAnchor = lastSyncTime ?? Date().addingTimeInterval(-86400 * 30) // Default 30-day lookback
            logger.info("Pulling incremental changes from remote container since \(pullAnchor)...")
            let pulledChanges = try await provider.pullChanges(since: pullAnchor)

            if !pulledChanges.isEmpty {
                logger.info("Successfully pulled \(pulledChanges.count) updates. Processing...")
                await DownloadQueue.shared.enqueue(pulledChanges)

                // 3. APPLY changes to local storage engines
                await applyPulledChanges()
            }

            syncProgress = 1.0
            syncState = .idle
            lastSyncTime = Date()
            UserDefaults.standard.set(lastSyncTime, forKey: "com.swiftcode.cloud.sync.last_sync_time")
            logger.info("Sync operation completed successfully.")
        } catch {
            logger.error("Sync operation encountered an error: \(error.localizedDescription, privacy: .public)")
            syncState = .error
            syncProgress = 0.0
            throw error
        }
    }

    // MARK: - Local Database Synchronization & Merge Hooks

    private func applyPulledChanges() async {
        let pending = await DownloadQueue.shared.getPending()
        guard !pending.isEmpty else { return }

        for payload in pending {
            do {
                switch payload.table {
                case "projects":
                    try await mergeLocalProjects(payload: payload)
                case "snippets":
                    try await mergeLocalSnippets(payload: payload)
                case "chat_history":
                    try await mergeLocalChatHistory(payload: payload)
                case "settings":
                    try await mergeLocalSettings(payload: payload)
                default:
                    logger.warning("Unrecognized sync payload table: \(payload.table)")
                }
                await DownloadQueue.shared.remove(payload.resourceID)
            } catch {
                logger.error("Error merging payload \(payload.resourceID): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func mergeLocalProjects(payload: SyncPayload) async throws {
        // Decode remote repository structure
        struct RemoteRepo: Codable {
            let id: String
            let name: String
            let owner: String
            let repository_url: String
            let default_branch: String?
            let local_project_path: String?
        }

        let remote = try JSONDecoder().decode(RemoteRepo.self, from: payload.data)
        guard let uuid = UUID(uuidString: remote.id) else { return }

        await MainActor.run {
            let appSettings = AppSettings.shared
            if let idx = appSettings.savedRepositories.firstIndex(where: { $0.id == uuid }) {
                // Update local repository record if remote is newer
                var local = appSettings.savedRepositories[idx]
                local.name = remote.name
                local.owner = remote.owner
                local.repositoryURL = remote.repository_url
                local.defaultBranch = remote.default_branch ?? "main"
                local.localProjectPath = remote.local_project_path
                appSettings.savedRepositories[idx] = local
            } else {
                // Add new remote repository securely
                let newRepo = SavedRepository(
                    id: uuid,
                    name: remote.name,
                    owner: remote.owner,
                    repositoryURL: remote.repository_url,
                    defaultBranch: remote.default_branch ?? "main",
                    localProjectPath: remote.local_project_path
                )
                appSettings.addRepository(newRepo)
            }
        }
    }

    private func mergeLocalSnippets(payload: SyncPayload) async throws {
        struct RemoteSnippet: Codable {
            let id: String
            let title: String
            let content: String
            let language: String?
            let tags: [String]?
        }

        let remote = try JSONDecoder().decode(RemoteSnippet.self, from: payload.data)
        guard let uuid = UUID(uuidString: remote.id) else { return }

        // Let's dynamically read and merge using a helper or read current list
        // Note: we'll load/save using CodeSnippetStore.save / load
        // But since CodeSnippet is private to SnippetsLibraryView, we can decode as general dict,
        // or re-use the JSON format. Let's perform a direct merge in UserDefaults.
        let key = "com.swiftcode.snippets"
        guard let savedData = UserDefaults.standard.data(forKey: key),
              var list = try? JSONSerialization.jsonObject(with: savedData) as? [[String: Any]] else {
            return
        }

        if let idx = list.firstIndex(where: { ($0["id"] as? String) == remote.id }) {
            var item = list[idx]
            item["title"] = remote.title
            item["code"] = remote.content
            item["language"] = remote.language ?? "Swift"
            list[idx] = item
        } else {
            let newItem: [String: Any] = [
                "id": remote.id,
                "title": remote.title,
                "code": remote.content,
                "language": remote.language ?? "Swift",
                "category": "Utilities",
                "isFavorite": false,
                "isPinned": false
            ]
            list.append(newItem)
        }

        if let updatedData = try? JSONSerialization.data(withJSONObject: list) {
            UserDefaults.standard.set(updatedData, forKey: key)
        }
    }

    private func mergeLocalChatHistory(payload: SyncPayload) async throws {
        // App Support conversations path: conversations.json
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let conversationsURL = paths[0].appendingPathComponent("SwiftCode/conversations.json")

        guard FileManager.default.fileExists(atPath: conversationsURL.path),
              let savedData = try? Data(contentsOf: conversationsURL),
              var list = try? JSONSerialization.jsonObject(with: savedData) as? [[String: Any]] else {
            return
        }

        if let remoteObj = try? JSONSerialization.jsonObject(with: payload.data) as? [String: Any],
           let sessionID = remoteObj["session_id"] as? String {

            if let idx = list.firstIndex(where: { ($0["id"] as? String) == sessionID }) {
                var local = list[idx]
                local["messages"] = remoteObj["messages"]
                list[idx] = local
            } else {
                let newSession: [String: Any] = [
                    "id": sessionID,
                    "title": (remoteObj["title"] as? String) ?? "Synced Conversation",
                    "messages": remoteObj["messages"] ?? [],
                    "modelID": "openai/gpt-4o",
                    "createdAt": Date().timeIntervalSince1970
                ]
                list.append(newSession)
            }

            let updatedData = try JSONSerialization.data(withJSONObject: list, options: .prettyPrinted)
            try updatedData.write(to: conversationsURL, options: .atomic)
        }
    }

    private func mergeLocalSettings(payload: SyncPayload) async throws {
        struct RemoteSetting: Codable {
            let key: String
            let value: String
        }

        let remote = try JSONDecoder().decode(RemoteSetting.self, from: payload.data)

        // Ensure settings are merged on the Main thread safely
        await MainActor.run {
            UserDefaults.standard.set(remote.value, forKey: remote.key)
        }
    }

    // MARK: - Offline Queue Helpers (invoked on local saves when online or offline)

    public func queueLocalChange(table: String, resourceID: String, data: Data) async {
        let payload = SyncPayload(
            resourceID: resourceID,
            table: table,
            data: data,
            lastModified: Date(),
            version: 1
        )
        await UploadQueue.shared.enqueue(payload)
        logger.info("Local change queued: \(table) -> \(resourceID)")

        // Trigger an automatic non-blocking sync if online
        Task {
            try? await triggerSync()
        }
    }
}
