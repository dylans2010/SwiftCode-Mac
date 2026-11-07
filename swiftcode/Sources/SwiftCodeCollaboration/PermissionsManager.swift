import Foundation

public struct PermissionEvent: Equatable {
    public let actorID: String
    public let title: String
    public let detail: String
    public let notifies: Bool
}

public enum CollaborationRole: String, Codable, CaseIterable {
    case owner
    case admin
    case editor
    case viewer
    case collaborator
}

public struct FileLock: Identifiable, Codable, Equatable {
    public let id: UUID
    public let path: String
    public let lockedBy: String
    public let timestamp: Date

    public init(path: String, lockedBy: String) {
        self.id = UUID()
        self.path = path
        self.lockedBy = lockedBy
        self.timestamp = Date()
    }
}

@MainActor
public final class PermissionsManager: ObservableObject {
    @Published public private(set) var memberRoles: [String: CollaborationRole] = [:]
    @Published public private(set) var memberPermissions: [String: TransferPermission] = [:]
    @Published public private(set) var lastEvent: PermissionEvent?

    public init(creatorID: String) {
        self.memberRoles[creatorID] = .owner
        self.memberPermissions[creatorID] = .owner
    }

    public func assignRole(_ role: CollaborationRole, to memberID: String, by actorID: String) -> Bool {
        guard let actorRole = memberRoles[actorID], canManageRoles(actorRole) else { return false }
        if role == .owner && actorRole != .owner { return false }
        memberRoles[memberID] = role
        memberPermissions[memberID] = defaultPermission(for: role)
        lastEvent = PermissionEvent(actorID: actorID, title: "Role Updated", detail: "\(memberID) is now \(role.rawValue.capitalized).", notifies: true)
        return true
    }

    public func updatePermission(_ permission: TransferPermission, for memberID: String, by actorID: String) -> Bool {
        guard canManageMembers(actorID: actorID) else { return false }
        guard memberRoles[memberID] != nil else { return false }
        memberPermissions[memberID] = permission
        lastEvent = PermissionEvent(actorID: actorID, title: "Permissions Updated", detail: "Live permissions changed for \(memberID).", notifies: true)
        return true
    }

    public func removeMember(_ memberID: String, by actorID: String) -> Bool {
        guard let actorRole = memberRoles[actorID], canManageRoles(actorRole) else { return false }
        guard memberRoles[memberID] != .owner else { return false }
        memberRoles.removeValue(forKey: memberID)
        memberPermissions.removeValue(forKey: memberID)
        lastEvent = PermissionEvent(actorID: actorID, title: "Collaborator Removed", detail: "\(memberID) removed from project.", notifies: true)
        return true
    }

    public func canManageMembers(actorID: String) -> Bool {
        guard let role = memberRoles[actorID] else { return false }
        return canManageRoles(role)
    }

    public func restoreState(memberRoles: [String: CollaborationRole]) {
        self.memberRoles = memberRoles
        self.memberPermissions = memberRoles.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = defaultPermission(for: entry.value)
        }
    }

    public func hasPermission(_ permission: TransferPermission.Scope, for memberID: String, projectPermission: TransferPermission) -> Bool {
        guard let role = memberRoles[memberID] else { return false }
        let effectivePermission = memberPermissions[memberID] ?? defaultPermission(for: role)
        if role == .owner { return true }
        if role == .admin { return effectivePermission.allows(permission) }
        return effectivePermission.allows(permission)
    }

    public func permission(for memberID: String) -> TransferPermission {
        guard let role = memberRoles[memberID] else { return TransferPermission.makePreset(.readOnly) }
        return memberPermissions[memberID] ?? defaultPermission(for: role)
    }

    private func canManageRoles(_ role: CollaborationRole) -> Bool {
        role == .owner || role == .admin
    }

    private func defaultPermission(for role: CollaborationRole) -> TransferPermission {
        switch role {
        case .owner:
            return .owner
        case .admin:
            return .makePreset(.fullAccess)
        case .editor:
            var permission = TransferPermission.makePreset(.limitedEdit)
            permission.isCollaborative = true
            permission.versionControl.push = true
            permission.versionControl.pull = true
            permission.versionControl.branchCreateDelete = true
            permission.versionControl.merge = true
            permission.versionControl.revert = true
            return permission
        case .viewer:
            return .makePreset(.readOnly)
        case .collaborator:
            var permission = TransferPermission.makePreset(.limitedEdit)
            permission.isCollaborative = true
            permission.versionControl.pull = true
            return permission
        }
    }
}
