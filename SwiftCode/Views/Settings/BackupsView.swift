import SwiftUI

@MainActor
public struct BackupsView: View {
    @State private var manifests: [BackupManifest] = []
    @State private var showingCreateSheet = false
    @State private var selectedManifest: BackupManifest?
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
                            Button {
                                showingCreateSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.app.fill")
                                    Text("Create Backup Snapshot...")
                                }
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
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
                            Button {
                                loadBackups()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
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
                                    Button {
                                        selectedManifest = manifest
                                    } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(manifest.createdAt.formatted(date: .long, time: .shortened))
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    Text("ID: \(manifest.backupID)")
                                                        .font(.system(.caption2, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                }

                                                Spacer()

                                                Image(systemName: "chevron.right")
                                                    .foregroundColor(.secondary)
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
                                    .buttonStyle(.plain)
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
        .sheet(isPresented: $showingCreateSheet) {
            CreateBackupView()
                .onDisappear {
                    loadBackups()
                }
        }
        .sheet(item: $selectedManifest) { manifest in
            NavigationStack {
                BackupDetailsView(manifest: manifest)
            }
            .onDisappear {
                loadBackups()
            }
        }
        .onAppear {
            loadBackups()
        }
    }

    private func loadBackups() {
        Task {
            BackupEngine.shared.loadLocalBackups()

            // If authenticated, also try to fetch remote cloud backups
            if AuthManager.shared.isAuthenticated {
                let provider = SupabaseCloudProvider(
                    url: URL(string: "https://secctbuzkfbketdihzui.supabase.co")!,
                    apiKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlY2N0YnV6a2Zia2V0ZGloenVpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDcxMDUwMDAsImV4cCI6MjAyNjg2MTAwMH0.mock-key-signature"
                )
                try? await BackupEngine.shared.fetchCloudBackups(cloudProvider: provider)
            }

            manifests = BackupEngine.shared.backups
        }
    }
}
