import SwiftUI
import SwiftCodeCollaboration

@MainActor
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
                GridRow { Text("Push").bold(); permissionCell(hasPermission(.push, for: memberID)) }
                GridRow { Text("Pull").bold(); permissionCell(hasPermission(.pull, for: memberID)) }
                GridRow { Text("Merge").bold(); permissionCell(hasPermission(.merge, for: memberID)) }
                GridRow { Text("Edit Files").bold(); permissionCell(hasPermission(.editFiles, for: memberID)) }
                GridRow { Text("Revert").bold(); permissionCell(hasPermission(.revert, for: memberID)) }
            }
            .font(.caption)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private func hasPermission(_ scope: TransferPermission.Scope, for memberID: String) -> Bool {
        manager.permissions.hasPermission(
            scope, for: memberID,
            projectPermission: manager.permissions.permission(for: actorID))
    }

    private func permissionCell(_ value: Bool) -> some View {
        Label(value ? "Allowed" : "Blocked", systemImage: value ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(value ? .green : .red)
    }
}
