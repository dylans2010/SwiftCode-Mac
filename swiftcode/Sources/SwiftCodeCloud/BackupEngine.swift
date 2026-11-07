import Foundation

public enum BackupError: Error, LocalizedError, Sendable, Equatable {
    case unauthenticated
    case missingTool(String)
    case archiveFailed(String)
    case backupNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Unauthorized: Appwrite authentication is required."
        case .missingTool(let tool):
            return "Backup needs the `\(tool)` command-line tool, which is not installed on this system."
        case .archiveFailed(let detail):
            return "Backup archive failed: \(detail)"
        case .backupNotFound(let filename):
            return "Backup archive file not found: \(filename)"
        }
    }
}

@MainActor
public final class BackupEngine {
    public static let shared = BackupEngine()

    public static let cloudBucket = "backups"

    public private(set) var isCreatingBackup = false
    public private(set) var isRestoring = false
    public private(set) var backupProgress: Double = 0.0
    public private(set) var backups: [BackupManifest] = []
    public private(set) var statusMessage: String?
    public private(set) var lastArchiveSHA256: String?

    private let fileManager: FileManager
    private let authManager: CloudAuthManager
    private let appSupportDirectory: URL
    private let createArchive: @Sendable (URL, URL) throws -> Void
    private let extractArchive: @Sendable (URL, URL) throws -> Int

    public init(
        authManager: CloudAuthManager = CloudAuthManager.shared,
        fileManager: FileManager = .default,
        appSupportDirectory: URL? = nil,
        createArchive: (@Sendable (URL, URL) throws -> Void)? = nil,
        extractArchive: (@Sendable (URL, URL) throws -> Int)? = nil
    ) {
        self.authManager = authManager
        self.fileManager = fileManager
        self.appSupportDirectory = appSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.createArchive = createArchive ?? Self.systemCreateArchive
        self.extractArchive = extractArchive ?? Self.systemExtractArchive
        loadLocalBackups()
    }

    public var localBackupsURL: URL {
        let url = appSupportDirectory.appendingPathComponent("SwiftCode/Backups", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public var appSupportStateURL: URL {
        appSupportDirectory.appendingPathComponent("SwiftCode", isDirectory: true)
    }

    public func loadLocalBackups() {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: localBackupsURL, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            var manifests: [BackupManifest] = []
            for file in files where file.pathExtension == "zip" {
                let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                manifests.append(BackupManifest(
                    backupID: file.deletingPathExtension().lastPathComponent,
                    createdAt: resourceValues.creationDate ?? Date(),
                    sizeInBytes: Int64(resourceValues.fileSize ?? 0),
                    filename: file.lastPathComponent,
                    isCloudStored: false))
            }
            self.backups = manifests.sorted { $0.createdAt > $1.createdAt }
        } catch {
        }
    }

    public func fetchCloudBackups(cloudProvider: CloudProvider) async throws {
        try requireAuthenticated()
        let remoteFiles = try await cloudProvider.storage.listObjects(bucket: Self.cloudBucket, prefix: nil)
        var cloudManifests: [BackupManifest] = []
        for file in remoteFiles where file.hasSuffix(".zip") {
            cloudManifests.append(BackupManifest(
                backupID: URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent,
                createdAt: Date(),
                sizeInBytes: 0,
                filename: file,
                isCloudStored: true))
        }
        let localAndCloud = self.backups.filter { !$0.isCloudStored } + cloudManifests
        self.backups = localAndCloud.sorted { $0.createdAt > $1.createdAt }
    }

    public func performBackup(cloudProvider: CloudProvider? = nil) async throws {
        try requireAuthenticated()

        isCreatingBackup = true
        backupProgress = 0.0
        statusMessage = "Starting backup snapshot..."
        defer {
            isCreatingBackup = false
            backupProgress = 1.0
        }

        let backupID = UUID().uuidString
        let tempZIPURL = localBackupsURL.appendingPathComponent("\(backupID).zip")

        let staging = fileManager.temporaryDirectory.appendingPathComponent("SwiftCodeBackup-\(backupID)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let entries = (try? fileManager.contentsOfDirectory(at: appSupportStateURL, includingPropertiesForKeys: nil)) ?? []
        let toArchive = entries.filter { $0.lastPathComponent != "Backups" }
        let totalFiles = Double(max(toArchive.count, 1))
        for (index, fileURL) in toArchive.enumerated() {
            try fileManager.copyItem(at: fileURL, to: staging.appendingPathComponent(fileURL.lastPathComponent))
            backupProgress = (Double(index + 1) / totalFiles) * 0.5
        }
        try createArchive(staging, tempZIPURL)

        let archiveData = try Data(contentsOf: tempZIPURL)
        lastArchiveSHA256 = SHA256Digest.hash(archiveData).map { String(format: "%02x", $0) }.joined()

        if let provider = cloudProvider {
            statusMessage = "Uploading backup snapshot to Appwrite backups bucket..."
            _ = try await provider.storage.upload(
                bucket: Self.cloudBucket,
                path: "\(backupID).zip",
                data: archiveData,
                contentType: "application/zip")
            backupProgress = 0.9
        }

        statusMessage = "Backup snapshot created successfully."
        loadLocalBackups()
    }

    public func restore(manifest: BackupManifest, cloudProvider: CloudProvider? = nil) async throws -> RestoreResult {
        try requireAuthenticated()

        isRestoring = true
        backupProgress = 0.0
        statusMessage = "Initializing restoration..."
        defer {
            isRestoring = false
            backupProgress = 1.0
        }

        let targetZIPURL = localBackupsURL.appendingPathComponent(manifest.filename)

        if manifest.isCloudStored, let provider = cloudProvider {
            statusMessage = "Downloading backup from Appwrite backups bucket..."
            let data = try await provider.storage.download(bucket: Self.cloudBucket, path: manifest.filename)
            try data.write(to: targetZIPURL)
            backupProgress = 0.4
        }

        guard fileManager.fileExists(atPath: targetZIPURL.path) else {
            return RestoreResult(isSuccess: false, errorMessage: "Backup archive file not found.")
        }

        let restoredData = try Data(contentsOf: targetZIPURL)
        lastArchiveSHA256 = SHA256Digest.hash(restoredData).map { String(format: "%02x", $0) }.joined()

        statusMessage = "Restoring application files..."

        let existingFiles = try fileManager.contentsOfDirectory(at: appSupportStateURL, includingPropertiesForKeys: nil)
        for file in existingFiles where file.lastPathComponent != "Backups" {
            try? fileManager.removeItem(at: file)
        }

        let count: Int
        do {
            count = try extractArchive(targetZIPURL, appSupportStateURL)
        } catch {
            return RestoreResult(isSuccess: false, errorMessage: "Failed to read zip archive: \(error.localizedDescription)")
        }
        backupProgress = 0.9

        await CloudSyncEngine.shared.triggerSync()

        statusMessage = "Restoration completed successfully."
        return RestoreResult(isSuccess: true, restoredFileCount: count)
    }

    public func delete(manifest: BackupManifest, cloudProvider: CloudProvider? = nil) async throws {
        try requireAuthenticated()
        statusMessage = "Deleting backup..."

        let localURL = localBackupsURL.appendingPathComponent(manifest.filename)
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        if manifest.isCloudStored, let provider = cloudProvider {
            try await provider.storage.delete(bucket: Self.cloudBucket, path: manifest.filename)
        }

        statusMessage = "Backup deleted successfully."
        loadLocalBackups()
    }

    private func requireAuthenticated() throws {
        guard authManager.isAuthenticated, authManager.swiftCodeID != nil else {
            throw BackupError.unauthenticated
        }
    }

    nonisolated static func systemCreateArchive(directory: URL, archive: URL) throws {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        guard !entries.isEmpty else {
            let emptyZIP = Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18))
            try emptyZIP.write(to: archive)
            return
        }
        try runTool("/usr/bin/zip", ["-r", "-q", archive.path, "."], currentDirectory: directory)
    }

    @discardableResult
    nonisolated static func systemExtractArchive(archive: URL, destination: URL) throws -> Int {
        try runTool("/usr/bin/unzip", ["-q", "-o", archive.path, "-d", destination.path], currentDirectory: nil)
        return (try? FileManager.default.contentsOfDirectory(atPath: destination.path))?.count ?? 0
    }

    private nonisolated static func runTool(_ path: String, _ arguments: [String], currentDirectory: URL?) throws {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw BackupError.missingTool(path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BackupError.archiveFailed(detail?.isEmpty == false ? detail! : "\(path) exited with status \(process.terminationStatus).")
        }
    }
}
