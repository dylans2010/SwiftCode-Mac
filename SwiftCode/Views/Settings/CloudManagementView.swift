import SwiftUI

@MainActor
public struct CloudManagementView: View {
    @AppStorage("com.swiftcode.cloud.syncEnabled") private var syncEnabled = false
    @State private var session: CloudSession?
    @State private var showingAuthSheet = false
    @State private var stats = CloudStatistics()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Section 1: User Account & Connection Status
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("User Session", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        if let session = session {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Signed in as:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(session.email)
                                    .font(.title3.bold())
                                if session.isGuest {
                                    Text("Anonymous Guest Account")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 4)

                            HStack(spacing: 12) {
                                NavigationLink(destination: SupabaseCloudView()) {
                                    Label("Cloud Dashboard", systemImage: "speedometer")
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    logout()
                                } label: {
                                    Text("Sign Out")
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Sign in to your SwiftCode Cloud account to enable automatic data sync and point-in-time cloud backups.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Button {
                                    showingAuthSheet = true
                                } label: {
                                    Label("Sign In or Register", systemImage: "lock.shield.fill")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 2: Sync Engine Configurations
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Continuous Cloud Sync", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        Toggle(isOn: $syncEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Sync Engine")
                                    .font(.subheadline.bold())
                                Text("Automatically keep your projects, AI chat histories, snippets, preferences, and workspace settings synchronized across all your devices.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(session == nil)
                        .onChange(of: syncEnabled) { _, newValue in
                            Task {
                                await CloudSyncEngine.shared.setSyncEnabled(newValue)
                            }
                        }

                        if session == nil {
                            Text("Please sign in above to enable cloud synchronization options.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 3: Sync Activity Stats
                if syncEnabled && session != nil {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Synchronization Metrics", systemImage: "chart.bar.xaxis")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                                Button {
                                    Task { await CloudSyncEngine.shared.triggerSync() }
                                } label: {
                                    Label("Sync Now", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            HStack(spacing: 20) {
                                StatCard(title: "Uploaded Records", value: "\(stats.totalUploadCount)", icon: "arrow.up.circle.fill", color: .green)
                                StatCard(title: "Downloaded Records", value: "\(stats.totalDownloadCount)", icon: "arrow.down.circle.fill", color: .blue)
                                StatCard(title: "Pending Changes", value: "\(stats.pendingUploadsCount)", icon: "clock.fill", color: .orange)
                            }

                            if let lastSync = stats.lastSyncTimestamp {
                                Text("Last synchronized at: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingAuthSheet) {
            CloudAuthViews(onSuccess: {
                loadSession()
            })
        }
        .onAppear {
            loadSession()
            loadStats()
        }
    }

    private func loadSession() {
        Task {
            session = try? await CloudSyncEngine.shared.getStatistics().isSyncing ? nil : nil
            // Load active session from mock-free keyring credentials if possible
            if let active = try? await CloudSyncEngine.shared.getStatistics() {
                // Read from Keychain
                if let key = KeychainService.shared.get(forKey: "supabase_session_active") {
                    session = try? JSONDecoder().decode(CloudSession.self, from: Data(key.utf8))
                }
            }
        }
    }

    private func loadStats() {
        Task {
            stats = await CloudSyncEngine.shared.getStatistics()
        }
    }

    private func logout() {
        KeychainService.shared.delete(forKey: "supabase_session_active")
        session = nil
        syncEnabled = false
        Task {
            await CloudSyncEngine.shared.setSyncEnabled(false)
        }
    }
}

// MARK: - Mini Stats Card Subview

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
}
