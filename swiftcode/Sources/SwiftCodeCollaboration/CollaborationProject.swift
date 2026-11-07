import Foundation

public struct CollaborationProject: Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var directoryURL: URL
    public var transferPermission: TransferPermission?

    public init(id: UUID = UUID(), name: String, directoryURL: URL,
                transferPermission: TransferPermission? = nil) {
        self.id = id
        self.name = name
        self.directoryURL = directoryURL
        self.transferPermission = transferPermission
    }

    public var fileCount: Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var count = 0
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                count += 1
            }
        }
        return count
    }
}

public struct TransferConfiguration: Codable, Sendable, Hashable {
    public var originPeerID: String
    public var permission: TransferPermission
    public var lastTransferSessionID: UUID?
    public var lastTransferDate: Date?

    public init(originPeerID: String, permission: TransferPermission,
                lastTransferSessionID: UUID? = nil, lastTransferDate: Date? = nil) {
        self.originPeerID = originPeerID
        self.permission = permission
        self.lastTransferSessionID = lastTransferSessionID
        self.lastTransferDate = lastTransferDate
    }
}
