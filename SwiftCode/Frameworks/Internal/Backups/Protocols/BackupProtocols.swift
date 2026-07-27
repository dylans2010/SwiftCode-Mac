import Foundation

/// Primary abstract seam governing point-in-time application snapshots and restores.
public protocol BackupProvider: Sendable {
    func createBackup(localURL: URL, completion: @escaping @Sendable (Result<BackupManifest, Error>) -> Void)
    func listBackups() async throws -> [BackupManifest]
    func restoreFromBackup(manifest: BackupManifest) async throws -> RestoreResult
    func deleteBackup(manifest: BackupManifest) async throws
}

/// Abstract seam managing the specific storage location of backup archives (Local vs Cloud).
public protocol BackupStorageProvider: Sendable {
    func store(archiveURL: URL, filename: String) async throws -> URL
    func retrieve(filename: String, toDestination destinationURL: URL) async throws
    func delete(filename: String) async throws
    func list() async throws -> [String]
}
