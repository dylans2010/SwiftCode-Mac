import Foundation

public struct SyncMetadata: Codable, Sendable, Equatable, Identifiable {
    public var id: String { tableName }
    public let tableName: String
    public let userID: String
    public let lastSyncedVersion: Int
    public let lastSyncedAt: Date
    public let syncAnchor: String?

    public init(
        tableName: String,
        userID: String,
        lastSyncedVersion: Int,
        lastSyncedAt: Date = Date(),
        syncAnchor: String? = nil
    ) {
        self.tableName = tableName
        self.userID = userID
        self.lastSyncedVersion = lastSyncedVersion
        self.lastSyncedAt = lastSyncedAt
        self.syncAnchor = syncAnchor
    }
}
