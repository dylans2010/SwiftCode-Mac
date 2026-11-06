// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Models/Project.swift — `ProjectTransferConfiguration` only
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeCollaboration/ProjectTransferConfiguration.swift.
// Verbatim apart from the header and the `public` access level.
//
// Why only this type from Project.swift: the other two types in that file
// already live in the destination under their own names —
// `CIBuildConfiguration` and `ProjectBuildSettings` are in
// `SwiftCodeIDECore/Model/SCProjectManifest.swift`, and `Project` itself
// is `SCProject` in the same file (same fields minus the GitHub token and
// this transfer configuration, same custom Codable shape, same
// `displayName`, and a stored `directoryURL` instead of the
// CodingManager-derived one). This struct is the one genuinely missing
// piece: the peer-transfer record. Its dependencies both exist in this
// target — `TransferPermission` (TransferPermission.swift) and
// `TransferAuditEntry` (TransferSession.swift) — which is why the
// SCProjectManifest header's "not ported: TransferPermission /
// TransferAuditEntry are outside this slice" no longer holds.
//
// Wiring hook (landing, optional): `SCProject` has no
// `transferConfiguration` field. If `.scproj` packages should round-trip
// peer-transfer state, add `public var transferConfiguration:
// ProjectTransferConfiguration?` to `SCProject` (with a CodingKey and
// decode/encode lines matching its existing optional fields). Nothing
// requires that for this type to compile or be used by the collaboration
// layer (`ProjectTransferManager` / `ProjectTransferSerializer`).

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
