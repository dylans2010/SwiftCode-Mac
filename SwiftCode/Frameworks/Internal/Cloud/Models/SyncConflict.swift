import Foundation

public struct SyncConflict: Codable, Identifiable, Sendable {
    public let id: UUID
    public let tableName: String
    public let primaryKey: String
    public let localData: Data
    public let cloudData: Data
    public let resolvedData: Data?
    public let detectedAt: Date
    public let resolvedAt: Date?
    public let resolvedBy: SyncConflictStrategy?

    public init(id: UUID = UUID(), tableName: String, primaryKey: String, localData: Data, cloudData: Data, resolvedData: Data? = nil, detectedAt: Date = Date(), resolvedAt: Date? = nil, resolvedBy: SyncConflictStrategy? = nil) {
        self.id = id
        self.tableName = tableName
        self.primaryKey = primaryKey
        self.localData = localData
        self.cloudData = cloudData
        self.resolvedData = resolvedData
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
        self.resolvedBy = resolvedBy
    }
}
