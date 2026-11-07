import SwiftUI
import SwiftCodeCollaboration

@MainActor
struct FilePermissionView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String
    @State private var filePath = ""

    var body: some View {
        List {
            Section("File Locking") {
                TextField("File path, e.g. Sources/Editor/CodeEditorView.swift", text: $filePath)
                HStack {
                    Button {
                        manager.lockFile(path: filePath, actorID: actorID)
                    } label: {
                        Label("Lock", systemImage: "lock.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        manager.unlockFile(path: filePath, actorID: actorID)
                    } label: {
                        Label("Unlock", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Active Locks") {
                if manager.fileLocks.isEmpty {
                    Text("No files are locked.")
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.fileLocks) { lock in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lock.path).font(.headline)
                        Text("Locked By \(lock.lockedBy)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Unlock") { manager.unlockFile(path: lock.path, actorID: actorID) }
                    }
                }
            }

            Section("Roles") {
                ForEach(manager.permissions.memberRoles.keys.sorted(), id: \.self) { memberID in
                    HStack {
                        Text(memberID)
                        Spacer()
                        Text(manager.permissions.memberRoles[memberID]?.rawValue.capitalized ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("File Permissions")
    }
}
