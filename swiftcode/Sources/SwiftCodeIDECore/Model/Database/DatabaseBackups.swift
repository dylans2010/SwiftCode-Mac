import Foundation

/// Backups — Legacy's `Core/DatabaseBackupManager.swift`, ported.
///
/// Deviation, recorded: Legacy registered backups in `UserDefaults`
/// (`com.swiftcode.database.backups`). A registry drifts the moment
/// a backup file is moved or deleted outside the app, so the port
/// lists backups by scanning the backup directory for the
/// timestamped names it writes (`<stem>_backup_yyyyMMdd_HHmmss.db`)
/// — the directory is the source of truth, as in Legacy's
/// file-copy approach itself. Backups are plain file copies of the
/// SQLite file, exactly as Legacy made them; restoring one copies it
/// back over the database file, so the caller must close any open
/// connection to that database first (the explorer window closes
/// and reopens the model around a restore).

public struct DatabaseBackup: Sendable, Equatable, Identifiable {
    public var id: URL { url }
    public var url: URL
    public var createdAt: Date
    public var sizeBytes: Int64

    public init(url: URL, createdAt: Date, sizeBytes: Int64) {
        self.url = url
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
    }
}

public enum DatabaseBackupError: Error, Equatable, Sendable {
    case databaseFileMissing(String)
    case backupFileMissing(URL)
}

extension DatabaseBackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .databaseFileMissing(let path): return "Database file not found at \(path)."
        case .backupFileMissing(let url): return "Backup file not found at \(url.path)."
        }
    }
}

@MainActor
public final class DatabaseBackupManager {
    public let databasePath: String
    public let backupDirectory: URL
    private let fileManager = FileManager.default

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// - Parameters:
    ///   - databasePath: the SQLite file to back up.
    ///   - backupDirectory: where backups live; defaults to the
    ///     database file's own directory, as Legacy did.
    public init(databasePath: String, backupDirectory: URL? = nil) {
        self.databasePath = databasePath
        self.backupDirectory = backupDirectory
            ?? URL(fileURLWithPath: databasePath).deletingLastPathComponent()
    }

    private var stem: String {
        URL(fileURLWithPath: databasePath).deletingPathExtension().lastPathComponent
    }

    private func backupName(for date: Date) -> String {
        "\(stem)_backup_\(Self.stampFormatter.string(from: date)).db"
    }

    private func isBackupFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix("\(stem)_backup_") && url.pathExtension == "db"
    }

    /// Copies the database file to a new timestamped backup.
    public func createBackup(date: Date = Date()) throws -> DatabaseBackup {
        guard fileManager.fileExists(atPath: databasePath) else {
            throw DatabaseBackupError.databaseFileMissing(databasePath)
        }
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let url = backupDirectory.appendingPathComponent(backupName(for: date))
        try fileManager.copyItem(atPath: databasePath, toPath: url.path)
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return DatabaseBackup(url: url, createdAt: date, sizeBytes: size)
    }

    /// Backups in the directory, newest first.
    public func listBackups() -> [DatabaseBackup] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }
        return urls.filter(isBackupFile).compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return DatabaseBackup(url: url, createdAt: values?.contentModificationDate ?? .distantPast,
                                  sizeBytes: Int64(values?.fileSize ?? 0))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Copies the backup back over the database file. The caller must
    /// have closed any open connection to the database first.
    public func restore(_ backup: DatabaseBackup) throws {
        guard fileManager.fileExists(atPath: backup.url.path) else {
            throw DatabaseBackupError.backupFileMissing(backup.url)
        }
        if fileManager.fileExists(atPath: databasePath) {
            try fileManager.removeItem(atPath: databasePath)
        }
        try fileManager.copyItem(at: backup.url, to: URL(fileURLWithPath: databasePath))
    }

    /// Deletes all but the `keeping` newest backups. Returns the
    /// number deleted.
    @discardableResult
    public func prune(keeping: Int) throws -> Int {
        let backups = listBackups()
        guard backups.count > keeping else { return 0 }
        var deleted = 0
        for backup in backups.dropFirst(keeping) {
            try fileManager.removeItem(at: backup.url)
            deleted += 1
        }
        return deleted
    }
}
