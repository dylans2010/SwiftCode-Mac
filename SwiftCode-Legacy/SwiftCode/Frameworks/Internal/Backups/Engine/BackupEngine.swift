import Foundation
import ZIPFoundation
import CryptoKit
import os

private let logger = Logger(subsystem: "com.swiftcode.Backups", category: "BackupEngine")

@Observable
@MainActor
public final class BackupEngine {
    public static let shared = BackupEngine()

    public var isCreatingBackup = false
    public var isRestoring = false
    public var backupProgress: Double = 0.0
    public var backups: [BackupManifest] = []
    public var statusMessage: String?

    private let fileManager = FileManager.default

    private var localBackupsURL: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let backupsDir = paths[0].appendingPathComponent("SwiftCode/Backups", isDirectory: true)
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

    public func fetchCloudBackups(cloudProvider: CloudProvider) async throws {
        guard AuthManager.shared.isAuthenticated, let _ = AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "BackupEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite session is required."])
        }

        logger.info("Fetching remote cloud backups list...")
        let remoteFiles = try await cloudProvider.storage.listObjects(bucket: "backups", prefix: nil)

        var cloudManifests: [BackupManifest] = []
        for file in remoteFiles where file.hasSuffix(".zip") {
            let backupID = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
            let manifest = BackupManifest(
                backupID: backupID,
                createdAt: Date(),
                sizeInBytes: 0,
                filename: file,
                isCloudStored: true
            )
            cloudManifests.append(manifest)
        }

        let localAndCloud = self.backups.filter { !$0.isCloudStored } + cloudManifests
        self.backups = localAndCloud.sorted { $0.createdAt > $1.createdAt }
    }

    public func performBackup(cloudProvider: CloudProvider? = nil) async throws {
        guard AuthManager.shared.isAuthenticated, let swiftCodeID = AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "BackupEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication is required."])
        }

        isCreatingBackup = true
        backupProgress = 0.0
        statusMessage = "Starting backup snapshot..."
        defer {
            isCreatingBackup = false
            backupProgress = 1.0
        }

        let backupID = UUID().uuidString
        let tempZIPURL = localBackupsURL.appendingPathComponent("\(backupID).zip")

        logger.info("Preparing local archive of application state for user \(swiftCodeID)...")

        let filesToBackup = try fileManager.contentsOfDirectory(at: appSupportStateURL, includingPropertiesForKeys: nil)
        let archive = try Archive(url: tempZIPURL, accessMode: .create)

        let totalFiles = Double(filesToBackup.count)
        for (index, fileURL) in filesToBackup.enumerated() {
            if fileURL.lastPathComponent == "Backups" { continue }

            let relativePath = fileURL.lastPathComponent
            try archive.addEntry(with: relativePath, fileURL: fileURL)
            backupProgress = (Double(index + 1) / totalFiles) * 0.5
        }

        let archiveData = try Data(contentsOf: tempZIPURL)
        let sha256 = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        logger.info("Local backup archive hash computed: \(sha256)")

        if let provider = cloudProvider {
            statusMessage = "Uploading backup snapshot to Supabase..."
            logger.info("Uploading ZIP snapshot to Supabase backups bucket under user: \(swiftCodeID)...")

            _ = try await provider.storage.upload(
                bucket: "backups",
                path: "\(backupID).zip",
                data: archiveData,
                contentType: "application/zip"
            )
            backupProgress = 0.9
            logger.info("Successfully uploaded backup \(backupID) to Supabase backups bucket.")
        }

        statusMessage = "Backup snapshot created successfully."
        loadLocalBackups()
    }

    public func restore(manifest: BackupManifest, cloudProvider: CloudProvider? = nil) async throws -> RestoreResult {
        guard AuthManager.shared.isAuthenticated, let swiftCodeID = AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "BackupEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication is required."])
        }

        isRestoring = true
        backupProgress = 0.0
        statusMessage = "Initializing restoration..."
        defer {
            isRestoring = false
            backupProgress = 1.0
        }

        let targetZIPURL = localBackupsURL.appendingPathComponent(manifest.filename)

        if manifest.isCloudStored, let provider = cloudProvider {
            statusMessage = "Downloading backup from Supabase..."
            logger.info("Downloading remote ZIP backup from user's storage: \(manifest.filename)")
            let data = try await provider.storage.download(bucket: "backups", path: manifest.filename)
            try data.write(to: targetZIPURL)
            backupProgress = 0.4
        }

        guard fileManager.fileExists(atPath: targetZIPURL.path) else {
            logger.error("Restoration failed: target ZIP archive not found.")
            return RestoreResult(isSuccess: false, errorMessage: "Backup archive file not found.")
        }

        let restoredData = try Data(contentsOf: targetZIPURL)
        let restoredHash = SHA256.hash(data: restoredData).map { String(format: "%02x", $0) }.joined()
        logger.info("Verification: Target ZIP hash for restoration is: \(restoredHash)")

        statusMessage = "Restoring application files..."
        logger.info("Erasing current local application state (excluding Backups)...")

        let existingFiles = try fileManager.contentsOfDirectory(at: appSupportStateURL, includingPropertiesForKeys: nil)
        for file in existingFiles {
            if file.lastPathComponent == "Backups" { continue }
            try? fileManager.removeItem(at: file)
        }

        let archive: Archive
        do {
            archive = try Archive(url: targetZIPURL, accessMode: .read)
        } catch {
            logger.error("Restoration failed: invalid ZIP archive. \(error.localizedDescription)")
            return RestoreResult(isSuccess: false, errorMessage: "Failed to read zip archive: \(error.localizedDescription)")
        }

        var count = 0
        let totalEntries = max(Double(archive.reduce(0) { c, _ in c + 1 }), 1.0)
        for (index, entry) in archive.enumerated() {
            let destinationURL = appSupportStateURL.appendingPathComponent(entry.path)
            _ = try archive.extract(entry, to: destinationURL)
            count += 1
            backupProgress = 0.4 + (Double(index + 1) / totalEntries) * 0.5
        }

        await CloudSyncEngine.shared.triggerSync()

        statusMessage = "Restoration completed successfully."
        logger.info("Restoration completed successfully from snapshot: \(manifest.backupID)")
        return RestoreResult(isSuccess: true, restoredFileCount: count)
    }

    public func delete(manifest: BackupManifest, cloudProvider: CloudProvider? = nil) async throws {
        guard AuthManager.shared.isAuthenticated, let _ = AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "BackupEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication is required."])
        }

        statusMessage = "Deleting backup..."
        logger.info("Deleting backup manifest: \(manifest.backupID)...")

        let localURL = localBackupsURL.appendingPathComponent(manifest.filename)
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        if manifest.isCloudStored, let provider = cloudProvider {
            try await provider.storage.delete(bucket: "backups", path: manifest.filename)
            logger.info("Successfully deleted remote backup from Supabase backups bucket.")
        }

        statusMessage = "Backup deleted successfully."
        loadLocalBackups()
    }
}
