import Foundation

public struct InviteEvent: Equatable {
    public let actorID: String
    public let title: String
    public let detail: String
    public let notifies: Bool
}

public struct CollaborationInvite: Identifiable, Codable, Equatable {
    public enum Status: String, Codable, CaseIterable {
        case pending
        case accepted
        case revoked
    }

    public let id: UUID
    public let memberID: String
    public let role: CollaborationRole
    public let invitedBy: String
    public let sentAt: Date
    public var status: Status
    public var autoJoin: Bool

    public init(memberID: String, role: CollaborationRole, invitedBy: String, autoJoin: Bool = true) {
        self.id = UUID()
        self.memberID = memberID
        self.role = role
        self.invitedBy = invitedBy
        self.sentAt = Date()
        self.status = .pending
        self.autoJoin = autoJoin
    }
}

@MainActor
public final class InviteManager: ObservableObject {
    @Published public private(set) var invites: [CollaborationInvite] = []
    @Published public private(set) var lastEvent: InviteEvent?

    public func createInvite(memberID: String, role: CollaborationRole, actorID: String) {
        var invite = CollaborationInvite(memberID: memberID, role: role, invitedBy: actorID)
        invite.status = .accepted
        invites.insert(invite, at: 0)
        lastEvent = InviteEvent(actorID: actorID, title: "Invitation Sent", detail: "\(memberID) invited as \(role.rawValue.capitalized).", notifies: true)
    }

    public func revokeInvite(_ inviteID: UUID, actorID: String) {
        guard let index = invites.firstIndex(where: { $0.id == inviteID }) else { return }
        invites[index].status = .revoked
        lastEvent = InviteEvent(actorID: actorID, title: "Invitation Revoked", detail: "Invite withdrawn for \(invites[index].memberID).", notifies: true)
    }

    public func restoreState(invites: [CollaborationInvite]) {
        self.invites = invites
    }
}
