import Foundation

public struct CloudSessionInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let email: String?
    public let activeDeviceName: String
    public let providerType: CloudProviderType
    public let createdAt: Date
    public let expiresAt: Date?

    public init(id: String, userId: String, email: String?, activeDeviceName: String, providerType: CloudProviderType, createdAt: Date = Date(), expiresAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.email = email
        self.activeDeviceName = activeDeviceName
        self.providerType = providerType
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}
