import Foundation

public struct CloudSyncMetadata: Codable, Identifiable, Sendable {
    public let id: UUID
    public let resourceName: String
    public let lastSyncedAt: Date
    public let localVersion: Int
    public let serverVersion: Int
    public let isDirty: Bool
    public let hashValue: String

    public init(id: UUID = UUID(), resourceName: String, lastSyncedAt: Date = Date(), localVersion: Int, serverVersion: Int, isDirty: Bool = false, hashValue: String = "") {
        self.id = id
        self.resourceName = resourceName
        self.lastSyncedAt = lastSyncedAt
        self.localVersion = localVersion
        self.serverVersion = serverVersion
        self.isDirty = isDirty
        self.hashValue = hashValue
    }
}
