import Foundation

public protocol BackupProvider: Sendable {
    func createBackup(localURL: URL, completion: @escaping @Sendable (Result<BackupManifest, Error>) -> Void)
    func listBackups() async throws -> [BackupManifest]
    func restoreFromBackup(manifest: BackupManifest) async throws -> RestoreResult
    func deleteBackup(manifest: BackupManifest) async throws
}

public protocol BackupStorageProvider: Sendable {
    func store(archiveURL: URL, filename: String) async throws -> URL
    func retrieve(filename: String, toDestination destinationURL: URL) async throws
    func delete(filename: String) async throws
    func list() async throws -> [String]
}
