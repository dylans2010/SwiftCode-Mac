import Foundation

public struct BackupItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let path: String
    public let sizeBytes: Int64
    public let checksum: String
    public let resourceType: String // e.g. "project", "chat", "setting"

    public init(id: UUID = UUID(), path: String, sizeBytes: Int64, checksum: String, resourceType: String) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
        self.checksum = checksum
        self.resourceType = resourceType
    }
}

public struct BackupManifest: Codable, Identifiable, Sendable {
    public let id: UUID
    public let version: Int
    public let createdAt: Date
    public let items: [BackupItem]
    public let totalSizeBytes: Int64
    public let isEncrypted: Bool
    public let compressionMethod: String // "zip", "none"

    public init(id: UUID = UUID(), version: Int = 1, createdAt: Date = Date(), items: [BackupItem], totalSizeBytes: Int64, isEncrypted: Bool, compressionMethod: String) {
        self.id = id
        self.version = version
        self.createdAt = createdAt
        self.items = items
        self.totalSizeBytes = totalSizeBytes
        self.isEncrypted = isEncrypted
        self.compressionMethod = compressionMethod
    }
}
