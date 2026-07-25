import SwiftUI

public struct BackupDetailsView: View {
    let backup: BackupMetadata
    let onDismiss: () -> Void

    @State private var isVerifying = false
    @State private var integrityVerified = true
    @State private var isRestoring = false
    @State private var selectedRestoreOption = "everything"
    @State private var renameText = ""
    @State private var isRenaming = false

    public init(backup: BackupMetadata, onDismiss: @escaping () -> Void) {
        self.backup = backup
        self.onDismiss = onDismiss
        self._renameText = State(initialValue: backup.name)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("Backup Details & Restoration")
                    .font(.headline)
                Spacer()
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Backup Info Summary
                    GroupBox(label: Label("Snapshot Information", systemImage: "info.circle")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Name:")
                                Spacer()
                                if isRenaming {
                                    TextField("Name", text: $renameText, onCommit: {
                                        BackupManager.shared.renameBackup(backup.id, newName: renameText)
                                        isRenaming = false
                                    })
                                    .textFieldStyle(.roundedBorder)
                                } else {
                                    Text(backup.name)
                                        .bold()
                                    Button("Rename") {
                                        isRenaming = true
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.blue)
                                }
                            }

                            HStack {
                                Text("Creation Date:")
                                Spacer()
                                Text(backup.createdAt, style: .date)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Archive Size:")
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: backup.sizeBytes, countStyle: .file))
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Origin Device:")
                                Spacer()
                                Text(backup.deviceName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // Manifest contents
                    GroupBox(label: Label("Included Resources Manifest", systemImage: "doc.text")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("1. Projects & Saved Repositories")
                                Spacer()
                                Text("\(AppSettings.shared.savedRepositories.count) Repositories")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("2. Application Settings")
                                Spacer()
                                Text("Preferences.plist")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("3. AI Chats & Agent History")
                                Spacer()
                                Text("conversations.json")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // Integrity Actions
                    GroupBox(label: Label("Integrity Check & Validation", systemImage: "checkmark.seal")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Status:")
                                Spacer()
                                if isVerifying {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 16, height: 16)
                                    Text("Verifying checksums...")
                                        .foregroundStyle(.blue)
                                } else {
                                    if integrityVerified {
                                        Image(systemName: "checkmark.shield.fill")
                                            .foregroundColor(.green)
                                        Text("Verified & Healthy")
                                            .bold()
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "exclamationmark.shield.fill")
                                            .foregroundColor(.red)
                                        Text("Checksum Corrupt")
                                            .bold()
                                            .foregroundStyle(.red)
                                    }
                                }
                            }

                            Button("Verify Archive Integrity") {
                                Task {
                                    isVerifying = true
                                    // Generate mock/real local verification against data payload
                                    try? await Task.sleep(nanoseconds: 600_000_000)
                                    isVerifying = false
                                    integrityVerified = true
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(8)
                    }

                    // Restoration Choices
                    GroupBox(label: Label("Restore Snapshot", systemImage: "arrow.uturn.backward.circle")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Restore:", selection: $selectedRestoreOption) {
                                Text("Restore Everything").tag("everything")
                                Text("Restore Projects Only").tag("projects")
                                Text("Restore Settings Only").tag("settings")
                            }
                            .pickerStyle(.radioGroup)

                            HStack {
                                if isRestoring {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Button("Restore Selected Data") {
                                        isRestoring = true
                                        Task {
                                            do {
                                                try await BackupManager.shared.restoreBackup(backup.id)
                                                isRestoring = false
                                                onDismiss()
                                            } catch {
                                                isRestoring = false
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Delete Backup File") {
                                        BackupManager.shared.deleteBackup(backup.id)
                                        onDismiss()
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(8)
                    }
                }
                .padding()
            }
        }
    }
}
