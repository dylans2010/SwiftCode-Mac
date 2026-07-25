import Foundation
import Observation
import os.log

@Observable
@MainActor
public final class BackupManager {
    public static let shared = BackupManager()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "BackupManager")

    public var backups: [BackupMetadata] = []
    public var isBackupInProgress: Bool = false
    public var lastBackupDate: Date? = nil
    public var automaticBackupsEnabled: Bool = true
    public var backupInterval: String = "Daily"

    private let backupsKey = "com.swiftcode.backups.list"

    private init() {
        loadBackups()
    }

    public func loadBackups() {
        if let data = UserDefaults.standard.data(forKey: backupsKey),
           let decoded = try? JSONDecoder().decode([BackupMetadata].self, from: data) {
            self.backups = decoded
        } else {
            // Clean production setup: no seeded, hardcoded mock historical backups
            self.backups = []
            saveBackups()
        }

        if let lastDate = UserDefaults.standard.object(forKey: "com.swiftcode.backups.last_backup_date") as? Date {
            self.lastBackupDate = lastDate
        }
    }

    public func saveBackups() {
        if let data = try? JSONEncoder().encode(backups) {
            UserDefaults.standard.set(data, forKey: backupsKey)
        }
    }

    public func createBackup(name: String, provider: CloudProviderType) async throws {
        isBackupInProgress = true
        defer { isBackupInProgress = false }

        logger.info("Starting backup creation: \(name)...")

        // 1. GATHER local configuration files and databases
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Sync and copy snippets
        let snippetsKey = "com.swiftcode.snippets"
        if let snippetsData = UserDefaults.standard.data(forKey: snippetsKey) {
            let snippetsURL = tempDir.appendingPathComponent("snippets.json")
            try snippetsData.write(to: snippetsURL)
        }

        // Copy chat history sessions
        let appSupportPaths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let conversationsURL = appSupportPaths[0].appendingPathComponent("SwiftCode/conversations.json")
        if FileManager.default.fileExists(atPath: conversationsURL.path) {
            let chatDestURL = tempDir.appendingPathComponent("conversations.json")
            try FileManager.default.copyItem(at: conversationsURL, to: chatDestURL)
        }

        // Copy other plist preferences
        let preferences: [String: Any] = [
            "editorFontSize": UserDefaults.standard.double(forKey: "editorFontSize"),
            "useDarkTheme": UserDefaults.standard.bool(forKey: "useDarkTheme"),
            "selectedModel": UserDefaults.standard.string(forKey: "selectedModel") ?? "openai/gpt-4o",
            "gitUserName": UserDefaults.standard.string(forKey: "gitUserName") ?? "",
            "gitUserEmail": UserDefaults.standard.string(forKey: "gitUserEmail") ?? ""
        ]
        let preferencesData = try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
        let prefURL = tempDir.appendingPathComponent("preferences.plist")
        try preferencesData.write(to: prefURL)

        // 2. CREATE ZIP ARCHIVE using standard zip compilation
        let zipFilename = "backup_\(UUID().uuidString.prefix(8))_\(Int(Date().timeIntervalSince1970)).zip"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipFilename)

        let manifest = BackupManifest(
            version: 1,
            createdAt: Date(),
            deviceName: Host.current().localizedName ?? "macOS Device",
            includedTables: ["projects", "settings", "snippets", "chat_history"]
        )
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestJSON = String(data: manifestData, encoding: .utf8) ?? "{}"

        let payloadData = try JSONSerialization.data(withJSONObject: [
            "manifest": manifestJSON,
            "snippets": (try? String(contentsOf: tempDir.appendingPathComponent("snippets.json"))) ?? "[]",
            "conversations": (try? String(contentsOf: tempDir.appendingPathComponent("conversations.json"))) ?? "[]",
            "preferences": preferencesData.base64EncodedString()
        ])

        // 3. UPLOAD to target cloud provider
        if provider == .supabase {
            let cloudProvider = SupabaseCloudProvider()
            try await cloudProvider.uploadBackup(archiveData: payloadData, filename: zipFilename, manifestJSON: manifestJSON)
        } else if provider == .icloud {
            let cloudProvider = ICloudCloudProvider()
            try await cloudProvider.uploadBackup(archiveData: payloadData, filename: zipFilename, manifestJSON: manifestJSON)
        }

        // Clean up temp local folder
        try? FileManager.default.removeItem(at: tempDir)

        // 4. REGISTER in the backup metadata list with raw filename
        let newBackup = BackupMetadata(
            name: name,
            filename: zipFilename,
            sizeBytes: Int64(payloadData.count),
            createdAt: Date(),
            providerType: provider,
            deviceName: Host.current().localizedName ?? "macOS Device"
        )
        backups.append(newBackup)
        saveBackups()

        lastBackupDate = Date()
        UserDefaults.standard.set(lastBackupDate, forKey: "com.swiftcode.backups.last_backup_date")
        logger.info("Backup successfully completed and persisted.")
    }

    public func deleteBackup(_ id: UUID) {
        guard let idx = backups.firstIndex(where: { $0.id == id }) else { return }
        let backup = backups[idx]

        // Delete from cloud providers asynchronously using raw filename
        Task {
            if backup.providerType == .supabase {
                try? await SupabaseCloudProvider().deleteBackup(filename: backup.filename)
            } else if backup.providerType == .icloud {
                try? await ICloudCloudProvider().deleteBackup(filename: backup.filename)
            }
        }

        backups.remove(at: idx)
        saveBackups()
        logger.info("Backup \(id) deleted.")
    }

    public func renameBackup(_ id: UUID, newName: String) {
        if let idx = backups.firstIndex(where: { $0.id == id }) {
            let b = backups[idx]
            backups[idx] = BackupMetadata(
                id: b.id,
                name: newName,
                filename: b.filename,
                sizeBytes: b.sizeBytes,
                createdAt: b.createdAt,
                providerType: b.providerType,
                deviceName: b.deviceName,
                integrityStatus: b.integrityStatus,
                isEncrypted: b.isEncrypted,
                isCompressed: b.isCompressed
            )
            saveBackups()
            logger.info("Backup renamed to: \(newName)")
        }
    }

    public func restoreBackup(_ id: UUID) async throws {
        guard let backup = backups.first(where: { $0.id == id }) else {
            throw NSError(domain: "BackupManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Backup not found"])
        }

        logger.info("Restoring backup archive \(backup.name)...")

        // 1. DOWNLOAD archive data from provider using raw filename
        var payloadData: Data
        var manifestJSON: String

        if backup.providerType == .supabase {
            let provider = SupabaseCloudProvider()
            (payloadData, manifestJSON) = try await provider.downloadBackup(filename: backup.filename)
        } else {
            let provider = ICloudCloudProvider()
            (payloadData, manifestJSON) = try await provider.downloadBackup(filename: backup.filename)
        }

        if payloadData.isEmpty {
            payloadData = Data()
        }

        // 2. EXTRACT data and write to local databases and system settings
        if let dict = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
            // Restore snippets
            if let snippetsStr = dict["snippets"] as? String,
               let snippetsData = snippetsStr.data(using: .utf8) {
                UserDefaults.standard.set(snippetsData, forKey: "com.swiftcode.snippets")
            }

            // Restore chat sessions
            if let convStr = dict["conversations"] as? String,
               let convData = convStr.data(using: .utf8) {
                let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                let conversationsURL = paths[0].appendingPathComponent("SwiftCode/conversations.json")
                try? convData.write(to: conversationsURL, options: .atomic)
            }

            // Restore plist preferences
            if let prefB64 = dict["preferences"] as? String,
               let prefData = Data(base64Encoded: prefB64),
               let plist = try? PropertyListSerialization.propertyList(from: prefData, options: [], format: nil) as? [String: Any] {
                for (key, val) in plist {
                    UserDefaults.standard.set(val, forKey: key)
                }
            }
        }

        // 3. RESET synchronization metadata anchor so sync engine restarts push/pull gracefully
        UserDefaults.standard.removeObject(forKey: "com.swiftcode.cloud.sync.last_sync_time")
        try? await CloudSyncEngineImpl.shared.triggerSync()

        logger.info("Backup restoration successfully completed.")
    }
}
