import Foundation

/// Backup provider seams (Legacy
/// `SwiftCode/Frameworks/Internal/Backups/Protocols/BackupProtocols.swift`,
/// Dylan's own code, ported under MIT). The concrete types they reference —
/// `BackupManifest` and `RestoreResult` — are the gap-closure ports in this
/// same target (`BackupModels.swift`); the engine that implements them is
/// the gap-closure `BackupEngine`. These protocols are the abstraction
/// Legacy's backup UI and cloud sync programmed against, so they land here
/// rather than being re-declared by callers.

/// Primary abstract seam governing point-in-time application snapshots and restores.
public protocol BackupProvider: Sendable {
    func createBackup(localURL: URL, completion: @escaping @Sendable (Result<BackupManifest, Error>) -> Void)
    func listBackups() async throws -> [BackupManifest]
    func restoreFromBackup(manifest: BackupManifest) async throws -> RestoreResult
    func deleteBackup(manifest: BackupManifest) async throws
}

/// Abstract seam managing the specific storage location of backup archives (local vs cloud).
public protocol BackupStorageProvider: Sendable {
    func store(archiveURL: URL, filename: String) async throws -> URL
    func retrieve(filename: String, toDestination destinationURL: URL) async throws
    func delete(filename: String) async throws
    func list() async throws -> [String]
}
