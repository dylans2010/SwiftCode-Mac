import Foundation

public struct SyncPayload: Codable, Sendable {
    public let resourceID: String
    public let table: String
    public let data: Data
    public let lastModified: Date
    public let version: Int

    public init(resourceID: String, table: String, data: Data, lastModified: Date, version: Int) {
        self.resourceID = resourceID
        self.table = table
        self.data = data
        self.lastModified = lastModified
        self.version = version
    }
}

public protocol SyncProvider: AnyObject, Sendable {
    func pushChanges(_ payloads: [SyncPayload]) async throws -> [String]
    func pullChanges(since lastSync: Date) async throws -> [SyncPayload]
}
