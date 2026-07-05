import Foundation

enum TransferSessionState: String, Codable {
    case discovered
    case connecting
    case authorizing
    case transferring
    case paused
    case completed
    case failed
    case rejected
}

public struct TransferAuditEntry: Identifiable, Codable, Hashable {
    public let id: UUID
    let timestamp: Date
    let actor: String
    let action: String
    let path: String?
    let allowed: Bool
    let detail: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), actor: String, action: String, path: String? = nil, allowed: Bool, detail: String) {
        self.id = id
        self.timestamp = timestamp
        self.actor = actor
        self.action = action
        self.path = path
        self.allowed = allowed
        self.detail = detail
    }
}

struct TransferParticipant: Codable, Hashable {
    let peerID: String
    let displayName: String
}

struct TransferSession: Identifiable, Codable, Hashable {
    public let id: UUID
    var projectID: UUID
    var projectName: String
    var sender: TransferParticipant
    var receiver: TransferParticipant?
    var permission: TransferPermission
    var state: TransferSessionState
    var progress: Double
    var bytesTransferred: Int64
    var totalBytes: Int64
    var transferredFiles: Int
    var totalFiles: Int
    var lastUpdated: Date
    var resumableToken: String
    var auditLog: [TransferAuditEntry]
    var checksum: String?
    var isEncrypted: Bool

    init(
        id: UUID = UUID(),
        projectID: UUID,
        projectName: String,
        sender: TransferParticipant,
        receiver: TransferParticipant? = nil,
        permission: TransferPermission,
        state: TransferSessionState = .discovered,
        progress: Double = 0,
        bytesTransferred: Int64 = 0,
        totalBytes: Int64 = 0,
        transferredFiles: Int = 0,
        totalFiles: Int = 0,
        lastUpdated: Date = Date(),
        resumableToken: String = UUID().uuidString,
        auditLog: [TransferAuditEntry] = [],
        checksum: String? = nil,
        isEncrypted: Bool = true
    ) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.sender = sender
        self.receiver = receiver
        self.permission = permission
        self.state = state
        self.progress = progress
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.transferredFiles = transferredFiles
        self.totalFiles = totalFiles
        self.lastUpdated = lastUpdated
        self.resumableToken = resumableToken
        self.auditLog = auditLog
        self.checksum = checksum
        self.isEncrypted = isEncrypted
    }
}
