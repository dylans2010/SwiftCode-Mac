import Foundation

/// Errors from the backup engine. The auth case mirrors Legacy's
/// `NSError(domain: "BackupEngine", code: 401)`; the rest name the
/// tool or file that failed instead of wrapping a bare `NSError`.
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

/// Point-in-time backup orchestration, ported from Legacy's
/// `Frameworks/Internal/Backups/Engine/BackupEngine.swift`
/// (249 lines) onto the `CloudProvider` seam.
///
/// Legacy used ZIPFoundation + CryptoKit and read the shared
/// `AuthManager` directly; this engine uses the system archivers
/// (`/usr/bin/zip` to create, `/usr/bin/unzip` to extract — the
/// same precedent as `SwiftCodeExtensions.PackageService`, which
/// extracts with `/usr/bin/unzip` on both macOS and Linux), the
/// pure-Swift `SHA256Digest` already in this target, and an
/// injected `CloudAuthManager` (defaulting to the shared one) so
/// tests can substitute one backed by a stub transport.
///
/// Behaviour is Legacy's, including the sharp edges, which are
/// documented rather than softened:
/// - Every operation requires an authenticated Appwrite session and
///   a SwiftCode id; otherwise it throws `.unauthenticated`.
/// - `performBackup` archives the whole `Application
///   Support/SwiftCode` directory except the `Backups` folder
///   itself, and uploads the ZIP to the `backups` bucket when a
///   provider is given. The archive hash is computed (and kept in
///   `lastArchiveSHA256`) but, as in Legacy, is not compared
///   against anything on restore — Legacy logged it only.
/// - `restore` **erases the current local application state**
///   (everything under `Application Support/SwiftCode` except
///   `Backups`) before extracting, exactly as Legacy did. Callers
///   must confirm with the user first; there is no undo.
/// - `fetchCloudBackups` stamps cloud manifests with `Date()` and
///   size `0` — Legacy had no remote metadata to fill those in
///   (the Storage list call returns ids, and the engine never
///   fetched per-file metadata). The values are placeholders, kept
///   as Legacy kept them.
/// - The bucket is named `backups` and the log/status strings say
///   "Supabase backups bucket" in Legacy; the calls go through
///   `cloudProvider.storage`, i.e. Appwrite Storage — Legacy's
///   naming confusion, not a Supabase dependency (see
///   `specs/ide/cloud-accounts.md` §8). This port says Appwrite.
///
/// The archive/unarchive steps are injected closures (defaulting
/// to the system tools) so tests can substitute fakes and no test
/// ever shells out or touches the real Application Support
/// directory.
@MainActor
public final class BackupEngine {
    public static let shared = BackupEngine()

    /// The bucket Legacy used for snapshots.
    public static let cloudBucket = "backups"

    public private(set) var isCreatingBackup = false
    public private(set) var isRestoring = false
    public private(set) var backupProgress: Double = 0.0
    public private(set) var backups: [BackupManifest] = []
    public private(set) var statusMessage: String?
    /// SHA-256 hex of the most recent archive this engine created
    /// (Legacy logged it; keeping it here makes it observable).
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

    /// `Application Support/SwiftCode/Backups`, created on demand.
    public var localBackupsURL: URL {
        let url = appSupportDirectory.appendingPathComponent("SwiftCode/Backups", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `Application Support/SwiftCode` — the state that gets
    /// snapshotted and, on restore, erased (except `Backups`).
    public var appSupportStateURL: URL {
        appSupportDirectory.appendingPathComponent("SwiftCode", isDirectory: true)
    }

    /// Loads the `.zip` files on local disk into `backups`, newest
    /// first. A failure leaves the previous list untouched, as in
    /// Legacy.
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
            // Legacy logged and kept the previous list; same here.
        }
    }

    /// Lists the ZIP snapshots in the remote `backups` bucket and
    /// merges them with the local list (no duplicates: local
    /// manifests are kept, cloud ones appended), newest first.
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

    /// Creates a ZIP snapshot of the application state and, when a
    /// provider is given, uploads it to the `backups` bucket.
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

        // 1. Gather app files to backup into a staging directory
        // (the `Backups` folder itself is never archived).
        let staging = fileManager.temporaryDirectory.appendingPathComponent("SwiftCodeBackup-\(backupID)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let entries = (try? fileManager.contentsOfDirectory(at: appSupportStateURL, includingPropertiesForKeys: nil)) ?? []
        let toArchive = entries.filter { $0.lastPathComponent != "Backups" }
        let totalFiles = Double(max(toArchive.count, 1))
        for (index, fileURL) in toArchive.enumerated() {
            try fileManager.copyItem(at: fileURL, to: staging.appendingPathComponent(fileURL.lastPathComponent))
            backupProgress = (Double(index + 1) / totalFiles) * 0.5 // up to 50% progress local
        }
        try createArchive(staging, tempZIPURL)

        // Compute local archive hash for integrity validation.
        let archiveData = try Data(contentsOf: tempZIPURL)
        lastArchiveSHA256 = SHA256Digest.hash(archiveData).map { String(format: "%02x", $0) }.joined()

        // 2. Upload to Cloud if provider is set.
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

    /// Restores the application state from a manifest: downloads
    /// the ZIP from the cloud first when needed, then erases the
    /// current local state (except `Backups`) and extracts. See
    /// the type documentation — the erase is Legacy's behaviour
    /// and is destructive. Notifies the sync engine afterwards so
    /// the restore does not cascade into a double upload, as in
    /// Legacy.
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

        // 1. Pull from cloud first if needed.
        if manifest.isCloudStored, let provider = cloudProvider {
            statusMessage = "Downloading backup from Appwrite backups bucket..."
            let data = try await provider.storage.download(bucket: Self.cloudBucket, path: manifest.filename)
            try data.write(to: targetZIPURL)
            backupProgress = 0.4
        }

        guard fileManager.fileExists(atPath: targetZIPURL.path) else {
            return RestoreResult(isSuccess: false, errorMessage: "Backup archive file not found.")
        }

        // Verify data integrity of ZIP before restoration (hash
        // computed as in Legacy; Legacy compared it against
        // nothing, so neither does this port).
        let restoredData = try Data(contentsOf: targetZIPURL)
        lastArchiveSHA256 = SHA256Digest.hash(restoredData).map { String(format: "%02x", $0) }.joined()

        statusMessage = "Restoring application files..."

        // 2. Erase existing local application state (excluding Backups).
        let existingFiles = try fileManager.contentsOfDirectory(at: appSupportStateURL, includingPropertiesForKeys: nil)
        for file in existingFiles where file.lastPathComponent != "Backups" {
            try? fileManager.removeItem(at: file)
        }

        // 3. Unzip files to restore state.
        let count: Int
        do {
            count = try extractArchive(targetZIPURL, appSupportStateURL)
        } catch {
            return RestoreResult(isSuccess: false, errorMessage: "Failed to read zip archive: \(error.localizedDescription)")
        }
        backupProgress = 0.9

        // 4. Notify Cloud Framework of the restore to avoid double upload cascades.
        await CloudSyncEngine.shared.triggerSync()

        statusMessage = "Restoration completed successfully."
        return RestoreResult(isSuccess: true, restoredFileCount: count)
    }

    /// Deletes a backup snapshot, locally and (when cloud-stored)
    /// remotely.
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

    // MARK: - Private

    private func requireAuthenticated() throws {
        guard authManager.isAuthenticated, authManager.swiftCodeID != nil else {
            throw BackupError.unauthenticated
        }
    }

    /// Creates a ZIP of the contents of `directory` at `archive`,
    /// via `/usr/bin/zip`. An empty directory becomes a valid
    /// empty ZIP (end-of-central-directory record only).
    static func systemCreateArchive(directory: URL, archive: URL) throws {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        guard !entries.isEmpty else {
            // Minimal valid empty ZIP: EOCD record only.
            let emptyZIP = Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18))
            try emptyZIP.write(to: archive)
            return
        }
        try runTool("/usr/bin/zip", ["-r", "-q", archive.path, "."], currentDirectory: directory)
    }

    /// Extracts `archive` into `destination` via `/usr/bin/unzip`
    /// and returns the number of files extracted (counted from the
    /// destination afterwards, top level only — the count Legacy
    /// reported was the number of archive entries).
    @discardableResult
    static func systemExtractArchive(archive: URL, destination: URL) throws -> Int {
        try runTool("/usr/bin/unzip", ["-q", "-o", archive.path, "-d", destination.path], currentDirectory: nil)
        return (try? FileManager.default.contentsOfDirectory(atPath: destination.path))?.count ?? 0
    }

    /// Runs a command-line tool, throwing `.missingTool` when the
    /// tool is absent and `.archiveFailed` with the tool's stderr
    /// when it exits non-zero.
    private static func runTool(_ path: String, _ arguments: [String], currentDirectory: URL?) throws {
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
