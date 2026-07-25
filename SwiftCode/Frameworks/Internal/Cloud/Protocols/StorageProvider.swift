import Foundation

public protocol StorageProvider: AnyObject, Sendable {
    func uploadFile(bucket: String, path: String, data: Data, contentType: String) async throws -> URL
    func downloadFile(bucket: String, path: String) async throws -> Data
    func deleteFile(bucket: String, path: String) async throws
}
