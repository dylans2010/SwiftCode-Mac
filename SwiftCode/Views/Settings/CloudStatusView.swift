import SwiftUI

@MainActor
public struct CloudStatusView: View {
    @State private var authManager = AuthManager.shared
    @State private var cloudManager = CloudManager.shared
    @State private var syncQueue = SyncQueue.shared
    @State private var pendingCount = 0

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cloud Subsystems Status")
                .font(.headline)

            GroupBox {
                VStack(spacing: 12) {
                    StatusRow(
                        title: "Appwrite Authentication",
                        status: authManager.isAuthenticated ? "Authenticated" : "Unauthenticated",
                        icon: "lock.shield",
                        color: authManager.isAuthenticated ? .green : .red
                    )

                    Divider()

                    StatusRow(
                        title: "Supabase Database Connection",
                        status: authManager.isAuthenticated ? "Connected" : "Offline",
                        icon: "cylinder.split.1x2",
                        color: authManager.isAuthenticated ? .green : .red
                    )

                    Divider()

                    StatusRow(
                        title: "Sync Engine Subsystem",
                        status: cloudManager.isSyncEnabled ? "Active" : "Disabled",
                        icon: "arrow.triangle.2.circlepath",
                        color: cloudManager.isSyncEnabled ? .green : .orange
                    )
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Telemetry Metrics")
                        .font(.subheadline.bold())

                    HStack {
                        Text("Pending Sync Changes:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(pendingCount) items")
                            .bold()
                    }

                    if let lastSync = cloudManager.lastSyncTime {
                        HStack {
                            Text("Last Successful Sync:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                .bold()
                        }
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .padding()
        .onAppear {
            Task {
                pendingCount = await syncQueue.getPendingUploadCount()
            }
        }
    }
}

struct StatusRow: View {
    let title: String
    let status: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)

            Text(title)
                .font(.body)

            Spacer()

            Text(status)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundColor(color)
                .cornerRadius(6)
        }
    }
}
