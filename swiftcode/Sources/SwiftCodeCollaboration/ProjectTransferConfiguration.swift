import Foundation

public struct ProjectTransferConfiguration: Codable, Hashable, Sendable {
    public var originPeerID: String?
    public var permission: TransferPermission
    public var lastTransferSessionID: UUID?
    public var lastTransferDate: Date?
    public var auditLog: [TransferAuditEntry]

    public init(originPeerID: String? = nil, permission: TransferPermission, lastTransferSessionID: UUID? = nil, lastTransferDate: Date? = nil, auditLog: [TransferAuditEntry] = []) {
        self.originPeerID = originPeerID
        self.permission = permission
        self.lastTransferSessionID = lastTransferSessionID
        self.lastTransferDate = lastTransferDate
        self.auditLog = auditLog
    }

    public static let owner = ProjectTransferConfiguration(permission: .owner)
}
