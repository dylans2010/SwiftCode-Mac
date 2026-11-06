// The project handle the collaboration and transfer system operates on.
//
// Legacy's collaboration family took SwiftCode's app `Project` model (id,
// name, directoryURL, file count, transfer settings). Ycode has no such
// model — the workspace is `WorkspaceSession` — so the ported system carries
// the small projection it actually needs. `CollaborationProject` is that
// projection: an identity, a display name, and the project directory on
// disk. Nothing else from Legacy's `Project` (file trees, CI build
// configuration, destinations, `project.json` metadata) is referenced here.

import Foundation

/// A project as the collaboration system sees it: identity, name, and the
/// directory on disk. Constructed by the IDE shell from the open workspace.
public struct CollaborationProject: Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var directoryURL: URL
    /// The transfer permission last applied to this project, if any.
    public var transferPermission: TransferPermission?

    public init(id: UUID = UUID(), name: String, directoryURL: URL,
                transferPermission: TransferPermission? = nil) {
        self.id = id
        self.name = name
        self.directoryURL = directoryURL
        self.transferPermission = transferPermission
    }

    /// Number of files under the project directory (directories excluded).
    /// Counted live; used for transfer progress totals.
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

/// Provenance recorded when a project arrives over a transfer. Legacy kept
/// this inside its `Project` model (`transferConfiguration`, written through
/// `ProjectSessionStore`); Ycode writes it as a `transfer.json` sidecar next
/// to the imported project (`ProjectTransferManager.importPackage`).
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
