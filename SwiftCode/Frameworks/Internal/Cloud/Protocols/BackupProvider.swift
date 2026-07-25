import Foundation

public protocol BackupProvider: AnyObject, Sendable {
    func uploadBackup(archiveData: Data, filename: String, manifestJSON: String) async throws
    func downloadBackup(filename: String) async throws -> (Data, String)
    func listBackups() async throws -> [String]
    func deleteBackup(filename: String) async throws
}
