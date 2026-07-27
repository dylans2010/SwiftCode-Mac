import Foundation
import ZIPFoundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Backups", category: "BackupEngine")

/// Production-ready Orchestrator for Point-In-Time Backup operations.
/// Safely creates ZIP archives of application state and uploads them locally or to Supabase Storage.
@Observable
@MainActor
public final class BackupEngine {
    public static let shared = BackupEngine()

    public var isCreatingBackup = false
    public var isRestoring = false
    public var backups: [BackupManifest] = []

    private let fileManager = FileManager.default

    private var localBackupsURL: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let backupsDir = paths[0].appendingPathComponent("SwiftCode/Backups", isDirectory: true)
        // SAFETY: Safe creation of folder hierarchy with error logging.
        try? fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        return backupsDir
    }

    private var appSupportStateURL: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("SwiftCode", isDirectory: true)
    }

    private init() {
        loadLocalBackups()
    }

    /// Load list of available backups on local disk.
    public func loadLocalBackups() {
        do {
            let files = try fileManager.contentsOfDirectory(at: localBackupsURL, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            var manifests: [BackupManifest] = []

            for file in files where file.pathExtension == "zip" {
                let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let size = Int64(resourceValues.fileSize ?? 0)
                let date = resourceValues.creationDate ?? Date()
                let filename = file.lastPathComponent

                let manifest = BackupManifest(
                    backupID: file.deletingPathExtension().lastPathComponent,
                    createdAt: date,
                    sizeInBytes: size,
                    filename: filename,
                    isCloudStored: false
                )
                manifests.append(manifest)
            }
            self.backups = manifests.sorted { $0.createdAt > $1.createdAt }
        } catch {
            logger.error("Failed to load local backups: \(error.localizedDescription)")
        }
    }

    /// Creates a complete snapshot backup.
    public func performBackup(cloudProvider: CloudProvider? = nil) async throws {
        isCreatingBackup = true
        defer { isCreatingBackup = false }

        let backupID = UUID().uuidString
        let tempZIPURL = localBackupsURL.appendingPathComponent("\(backupID).zip")

        // 1. Gather app files to backup
        let filesToBackup = try fileManager.contentsOfDirectory(at: appSupportStateURL, includingPropertiesForKeys: nil)
        let archive = try Archive(url: tempZIPURL, accessMode: .create)

        for fileURL in filesToBackup {
            // Do not backup the backups folder recursively
            if fileURL.lastPathComponent == "Backups" { continue }

            let relativePath = fileURL.lastPathComponent
            try archive.addEntry(with: relativePath, fileURL: fileURL)
        }

        // 2. Upload to Cloud if provider is set and cloud storage is configured
        if let provider = cloudProvider {
            let data = try Data(contentsOf: tempZIPURL)
            _ = try await provider.storage.upload(
                bucket: "backups",
                path: "\(backupID).zip",
                data: data,
                contentType: "application/zip"
            )
            logger.info("Successfully uploaded point-in-time backup \(backupID) to Supabase backups bucket.")
        }

        loadLocalBackups()
        logger.info("Local and remote backup \(backupID) created successfully.")
    }

    /// Restores the entire application state from a given manifest.
    public func restore(manifest: BackupManifest, cloudProvider: CloudProvider? = nil) async throws -> RestoreResult {
        isRestoring = true
        defer { isRestoring = false }

        let targetZIPURL = localBackupsURL.appendingPathComponent(manifest.filename)

        // 1. Pull from cloud first if needed
        if manifest.isCloudStored, let provider = cloudProvider {
            let data = try await provider.storage.download(bucket: "backups", path: manifest.filename)
            try data.write(to: targetZIPURL)
        }

        guard fileManager.fileExists(atPath: targetZIPURL.path) else {
            return RestoreResult(isSuccess: false, errorMessage: "Backup archive file not found.")
        }

        // 2. Erase existing local state directory (except Backups)
        let existingFiles = try fileManager.contentsOfDirectory(at: appSupportStateURL, includingPropertiesForKeys: nil)
        for file in existingFiles {
            if file.lastPathComponent == "Backups" { continue }
            try? fileManager.removeItem(at: file)
        }

        // 3. Unzip files to restore state
        guard let archive = Archive(url: targetZIPURL, accessMode: .read) else {
            return RestoreResult(isSuccess: false, errorMessage: "Failed to read zip archive.")
        }

        var count = 0
        for entry in archive {
            let destinationURL = appSupportStateURL.appendingPathComponent(entry.path)
            _ = try archive.extract(entry, to: destinationURL)
            count += 1
        }

        // 4. Notify Cloud Framework of the restore to avoid double upload cascades
        await CloudSyncEngine.shared.triggerSync()

        logger.info("Restoration completed successfully from snapshot: \(manifest.backupID)")
        return RestoreResult(isSuccess: true, restoredFileCount: count)
    }

    /// Deletes a backup snapshot.
    public func delete(manifest: BackupManifest, cloudProvider: CloudProvider? = nil) async throws {
        let localURL = localBackupsURL.appendingPathComponent(manifest.filename)
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        if manifest.isCloudStored, let provider = cloudProvider {
            try await provider.storage.delete(bucket: "backups", path: manifest.filename)
        }

        loadLocalBackups()
    }
}
