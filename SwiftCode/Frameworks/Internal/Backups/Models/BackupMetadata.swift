import Foundation

public struct BackupMetadata: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let sizeBytes: Int64
    public let createdAt: Date
    public let providerType: CloudProviderType
    public let deviceName: String
    public let integrityStatus: String // e.g. "verified", "corrupt"
    public let isEncrypted: Bool
    public let isCompressed: Bool

    public init(id: UUID = UUID(), name: String, sizeBytes: Int64, createdAt: Date = Date(), providerType: CloudProviderType, deviceName: String, integrityStatus: String = "verified", isEncrypted: Bool = true, isCompressed: Bool = true) {
        self.id = id
        self.name = name
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.providerType = providerType
        self.deviceName = deviceName
        self.integrityStatus = integrityStatus
        self.isEncrypted = isEncrypted
        self.isCompressed = isCompressed
    }
}
