import Foundation

@MainActor
public final class DatabaseBackupManager: ObservableObject {
    public static let shared = DatabaseBackupManager()

    @Published public var backupPaths: [String] = []

    private init() {
        loadBackups()
    }

    public func createBackup(connection: DatabaseConnection) throws -> String {
        guard connection.provider == .sqlite, let filePath = connection.sqliteFilePath else {
            throw DatabaseError.validationFailed("Backups are currently supported only for local SQLite connections.")
        }

        let fileURL = URL(fileURLWithPath: filePath)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())

        let backupFileName = "\(fileURL.deletingPathExtension().lastPathComponent)_backup_\(timestamp).db"
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupFileName)

        try FileManager.default.copyItem(at: fileURL, to: backupURL)

        let path = backupURL.path
        backupPaths.append(path)
        saveBackups()
        return path
    }

    public func restoreBackup(_ path: String, to connection: DatabaseConnection) throws {
        guard connection.provider == .sqlite, let targetPath = connection.sqliteFilePath else {
            throw DatabaseError.validationFailed("Backups are currently supported only for local SQLite connections.")
        }

        let backupURL = URL(fileURLWithPath: path)
        let targetURL = URL(fileURLWithPath: targetPath)

        if FileManager.default.fileExists(atPath: targetPath) {
            try FileManager.default.removeItem(at: targetURL)
        }

        try FileManager.default.copyItem(at: backupURL, to: targetURL)
    }

    private func loadBackups() {
        if let paths = UserDefaults.standard.stringArray(forKey: "com.swiftcode.database.backups") {
            self.backupPaths = paths
        }
    }

    private func saveBackups() {
        UserDefaults.standard.set(backupPaths, forKey: "com.swiftcode.database.backups")
    }
}
