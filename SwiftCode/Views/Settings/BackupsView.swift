import SwiftUI

@MainActor
public struct BackupsView: View {
    @State private var manifests: [BackupManifest] = []
    @State private var isCreating = false
    @State private var isRestoring = false
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Section 1: Creation Panel Control
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Create Snapshot", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        Text("Capture a point-in-time snapshot of all local preferences, projects list, syntax themes, and custom layout configurations. Snapshots can be stored securely on device or synced to Supabase backups bucket.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button(action: createBackup) {
                                HStack {
                                    if isCreating {
                                        ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                                    } else {
                                        Image(systemName: "plus.app.fill")
                                    }
                                    Text(isCreating ? "Creating Snapshot..." : "Create Backup Snapshot")
                                }
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isCreating || isRestoring)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Status banner if present
                if let message = statusMessage {
                    HStack {
                        Image(systemName: statusColor == .green ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(statusColor)
                        Text(message)
                            .font(.subheadline.bold())
                            .foregroundColor(statusColor)
                        Spacer()
                    }
                    .padding()
                    .background(statusColor.opacity(0.1))
                    .cornerRadius(8)
                    .transition(.opacity)
                }

                // Section 2: Browse Snapshots Lists Table
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Saved Backups (\(manifests.count))", systemImage: "tray.full.fill")
                                .font(.headline)
                                .foregroundColor(.indigo)
                            Spacer()
                        }

                        if manifests.isEmpty {
                            Text("No backup snapshots registered yet. Press 'Create Backup' to take your first point-in-time snapshot.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 30)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(manifests) { manifest in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(manifest.createdAt.formatted(date: .long, time: .shortened))
                                                    .font(.headline)
                                                Text("ID: \(manifest.backupID)")
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            HStack(spacing: 8) {
                                                Button("Restore") {
                                                    restore(manifest)
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .tint(.green)
                                                .disabled(isCreating || isRestoring)

                                                Button(role: .destructive) {
                                                    delete(manifest)
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.bordered)
                                                .disabled(isCreating || isRestoring)
                                            }
                                        }

                                        Divider()

                                        HStack {
                                            Label("\(Double(manifest.sizeInBytes) / 1024.0 / 1024.0, specifier: "%.2f") MB", systemImage: "doc.zipper")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Spacer()

                                            Label(manifest.isCloudStored ? "Cloud Bucket" : "Local Disk Only", systemImage: manifest.isCloudStored ? "icloud.fill" : "laptopcomputer")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding()
                                    .background(Color.secondary.opacity(0.06))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Point-In-Time Backups")
        .onAppear {
            loadBackups()
        }
    }

    private func loadBackups() {
        Task {
            BackupEngine.shared.loadLocalBackups()
            manifests = BackupEngine.shared.backups
        }
    }

    private func createBackup() {
        isCreating = true
        statusMessage = nil

        Task {
            do {
                try await BackupEngine.shared.performBackup()
                loadBackups()
                statusColor = .green
                statusMessage = "Backup snapshot created successfully."
            } catch {
                statusColor = .red
                statusMessage = "Failed to create snapshot: \(error.localizedDescription)"
            }
            isCreating = false
        }
    }

    private func restore(_ manifest: BackupManifest) {
        let alert = NSAlert()
        alert.messageText = "Restore Application State?"
        alert.informativeText = "Are you absolutely sure? This will fully overwrite all current settings, project paths, themes, and chats with the snapshot taken on \(manifest.createdAt.formatted(date: .abbreviated, time: .shortened)). This action cannot be undone."
        alert.addButton(withTitle: "Yes, Restore State")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical

        if alert.runModal() == .alertFirstButtonReturn {
            isRestoring = true
            statusMessage = nil

            Task {
                do {
                    let result = try await BackupEngine.shared.restore(manifest: manifest)
                    if result.isSuccess {
                        statusColor = .green
                        statusMessage = "Application state restored successfully with \(result.restoredFileCount) file nodes."
                    } else {
                        statusColor = .red
                        statusMessage = result.errorMessage ?? "Failed to apply state restoration."
                    }
                } catch {
                    statusColor = .red
                    statusMessage = "Failed to restore state: \(error.localizedDescription)"
                }
                isRestoring = false
                loadBackups()
            }
        }
    }

    private func delete(_ manifest: BackupManifest) {
        Task {
            do {
                try await BackupEngine.shared.delete(manifest: manifest)
                loadBackups()
            } catch {
                statusColor = .red
                statusMessage = "Failed to delete backup: \(error.localizedDescription)"
            }
        }
    }
}
