import SwiftUI

struct WorkspaceProfilesView: View {
    @StateObject private var manager = WorkspaceProfilesManager.shared
    @State private var draft = WorkspaceProfile.empty

    var body: some View {
        AdvancedToolScreen(title: "Workspace Profiles") {
            AdvancedToolCard(title: "Active Profile", subtitle: "Single source of truth for workspace settings") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manager.activeProfile?.name ?? "No Active Profile")
                            .font(.title3.weight(.semibold))
                        Text("Build: \(manager.activeProfile?.buildConfiguration ?? "n/a")")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(manager.activeProfile == nil ? Color.secondary : Color.green)
                        .font(.title2)
                }
            }

            AdvancedToolCard(title: "Create Workspace Profile") {
                TextField("Workspace Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                TextField("Build Configuration", text: $draft.buildConfiguration)
                    .textFieldStyle(.roundedBorder)
                Button("Create Profile", action: createProfile)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            AdvancedToolCard(title: "Available Profiles", subtitle: "Switching updates all profile-bound labels immediately") {
                if manager.profiles.isEmpty {
                    Text("No Profiles Yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name).font(.headline)
                                Text("Build: \(profile.buildConfiguration)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if manager.activeProfileID == profile.id {
                                Label("Active", systemImage: "bolt.fill")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.18), in: Capsule())
                            }
                            Button("Activate") { manager.switchTo(profile) }
                                .buttonStyle(.bordered)
                            Button(role: .destructive) { manager.delete(profile) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func createProfile() {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = draft.buildConfiguration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        manager.add(
            .init(
                id: UUID(),
                name: name,
                buildConfiguration: config.isEmpty ? "Debug" : config,
                environmentVariables: [:],
                preferences: [:]
            )
        )
        draft = .empty
    }
}
