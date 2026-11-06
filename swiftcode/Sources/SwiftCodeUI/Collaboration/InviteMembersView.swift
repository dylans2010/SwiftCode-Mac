// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Collaboration/InviteMembersView.swift
// Adapted for SwiftCode — two destination limits forced real changes, both
// recorded here rather than papered over:
//
// 1. Nearby peers: Legacy listed Multipeer peers via PeerSessionManager.
//    In the destination PeerSessionManager is INTERNAL to
//    SwiftCodeCollaboration (not public), so no nearby-peer list or
//    multipeer invite is reachable from SwiftCodeUI. The "Nearby
//    Collaborators" section is replaced by a manual invite: member ID +
//    role -> CollaborationManager.invite, which really calls
//    InviteManager.createInvite + PermissionsManager.assignRole. Search now
//    filters the current-collaborators list.
// 2. Permission toggles: Legacy toggled TransferPermission fields
//    (versionControl.push/merge, fileSystem.editFiles) directly, but those
//    stored properties — and makePreset / .owner — are INTERNAL to
//    SwiftCodeCollaboration, so no per-scope write is reachable from
//    SwiftCodeUI. A Toggle that did not persist would be a fake handler, so
//    the toggles become read-only status rows driven by the real public API
//    PermissionsManager.hasPermission(_:for:projectPermission:). Per-scope
//    editing needs a public per-scope mutation on PermissionsManager in the
//    backend (out of scope here: the destination repo must not be edited).
//
// Everything else is wired to the real backend: role changes and removal
// via PermissionsManager.assignRole / removeMember, the invite feed from
// InviteManager.invites with revoke via InviteManager.revokeInvite.

import SwiftUI
import SwiftCodeCollaboration

@MainActor
struct InviteMembersView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String
    @State private var newMemberID = ""
    @State private var newMemberRole: CollaborationRole = .collaborator
    @State private var searchText = ""

    var body: some View {
        List {
            inviteSection
            currentCollaboratorsSection
            inviteFeedSection
        }
        .navigationTitle("Invite Members")
        .searchable(text: $searchText)
    }

    private var inviteSection: some View {
        Section("Invite Member") {
            TextField("Member ID", text: $newMemberID)
            Picker("Role", selection: $newMemberRole) {
                ForEach(CollaborationRole.allCases, id: \.self) { role in
                    Text(role.rawValue.capitalized).tag(role)
                }
            }
            .pickerStyle(.segmented)
            Button("Invite") {
                manager.invite(memberID: newMemberID, role: newMemberRole, actorID: actorID)
                newMemberID = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(newMemberID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var currentCollaboratorsSection: some View {
        Section("Current Collaborators") {
            if filteredMembers.isEmpty {
                Text("No collaborators match.")
                    .foregroundStyle(.secondary)
            }
            ForEach(filteredMembers, id: \.self) { memberID in
                collaboratorRow(memberID: memberID)
            }
        }
    }

    private func collaboratorRow(memberID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(memberID)
                    Text(manager.permissions.memberRoles[memberID]?.rawValue.capitalized ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if memberID != actorID {
                    manageMenu(for: memberID)
                }
            }

            permissionRows(for: memberID)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private func manageMenu(for memberID: String) -> some View {
        Menu("Manage") {
            ForEach(CollaborationRole.allCases, id: \.self) { role in
                Button("Make \(role.rawValue.capitalized)") {
                    _ = manager.permissions.assignRole(role, to: memberID, by: actorID)
                }
            }
            Button("Kick User", role: .destructive) {
                _ = manager.permissions.removeMember(memberID, by: actorID)
            }
        }
    }

    private var inviteFeedSection: some View {
        Section("Invite Feed") {
            if manager.invites.invites.isEmpty {
                Text("No invites sent yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(manager.invites.invites) { invite in
                VStack(alignment: .leading, spacing: 4) {
                    Text(invite.memberID).font(.headline)
                    Text("\(invite.role.rawValue.capitalized) • \(invite.status.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    if invite.status == .pending || invite.status == .accepted {
                        Button("Revoke Invite", role: .destructive) {
                            manager.invites.revokeInvite(invite.id, actorID: actorID)
                        }
                    }
                }
            }
        }
    }

    private var filteredMembers: [String] {
        let members = manager.permissions.memberRoles.keys.sorted()
        if searchText.isEmpty { return members }
        return members.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    /// Read-only permission status. See the file header: per-scope writes
    /// are not reachable from SwiftCodeUI in the destination backend.
    @ViewBuilder
    private func permissionRows(for memberID: String) -> some View {
        permissionRow(label: "Can Push", scope: .push, memberID: memberID)
        permissionRow(label: "Can Merge", scope: .merge, memberID: memberID)
        permissionRow(label: "Can Edit Files", scope: .editFiles, memberID: memberID)
    }

    private func permissionRow(label: String, scope: TransferPermission.Scope, memberID: String) -> some View {
        let allowed = manager.permissions.hasPermission(
            scope, for: memberID,
            projectPermission: manager.permissions.permission(for: actorID))
        return HStack {
            Text(label)
            Spacer()
            Label(allowed ? "Allowed" : "Blocked",
                  systemImage: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(allowed ? .green : .red)
        }
        .font(.caption)
    }
}
