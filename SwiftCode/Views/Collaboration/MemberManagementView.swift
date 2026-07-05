import SwiftUI

struct MemberManagementView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String

    var body: some View {
        List {
            Section("Management Actions") {
                NavigationLink {
                    InviteMembersView(manager: manager, actorID: actorID)
                } label: {
                    Label("Invite New Members", systemImage: "person.badge.plus.fill")
                }
            }

            Section("All Members") {
                if manager.permissions.memberRoles.isEmpty {
                    Text("No Members Registered")
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.permissions.memberRoles.keys.sorted(), id: \.self) { memberID in
                    memberCard(memberID: memberID)
                }
            }
        }
        .navigationTitle("Member Management")
    }

    @ViewBuilder
    private func memberCard(memberID: String) -> some View {
        let role = manager.permissions.memberRoles[memberID]?.rawValue.capitalized ?? "Unknown"
        let permission = manager.permissions.permission(for: memberID)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(memberID).font(.headline)
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if memberID != actorID {
                    Menu {
                        ForEach(CollaborationRole.allCases, id: \.self) { role in
                            Button("Make \(role.rawValue.capitalized)") {
                                _ = manager.permissions.assignRole(role, to: memberID, by: actorID)
                            }
                        }
                        Button("Remove Collaborator", role: .destructive) {
                            _ = manager.permissions.removeMember(memberID, by: actorID)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.blue)
                    }
                } else {
                    Text("(You)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow { Text("Push").bold(); permissionCell(permission.versionControl.push) }
                GridRow { Text("Pull").bold(); permissionCell(permission.versionControl.pull) }
                GridRow { Text("Merge").bold(); permissionCell(permission.versionControl.merge) }
                GridRow { Text("Edit Files").bold(); permissionCell(permission.fileSystem.editFiles) }
                GridRow { Text("Revert").bold(); permissionCell(permission.versionControl.revert) }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func permissionCell(_ value: Bool) -> some View {
        Label(value ? "Allowed" : "Blocked", systemImage: value ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(value ? .green : .red)
    }
}
