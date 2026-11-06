import SwiftUI

@MainActor
public struct CloudSyncView: View {
    @State private var cloudManager = CloudManager.shared
    @State private var syncQueue = SyncQueue.shared
    @State private var isSyncing = false
    @State private var pendingCount = 0
    @State private var lastError: String?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cloud Synchronization Settings")
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Current Sync State:", systemImage: "clock.arrow.2.circlepath")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(cloudManager.syncState.rawValue.uppercased())
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(stateColor.opacity(0.15))
                            .foregroundColor(stateColor)
                            .cornerRadius(6)
                    }

                    if let lastSync = cloudManager.lastSyncTime {
                        HStack {
                            Text("Last Successful Sync:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.bold())
                        }
                    }

                    HStack {
                        Text("Pending Uploads Queue:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(pendingCount) items")
                            .font(.caption.bold())
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            if let error = lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            HStack(spacing: 12) {
                Button(action: triggerManualSync) {
                    HStack {
                        if isSyncing {
                            ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                        }
                        Text("Sync Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSyncing)

                Button("Retry Failed Sync") {
                    triggerManualSync()
                }
                .buttonStyle(.bordered)
                .disabled(isSyncing)

                Button("Refresh Status") {
                    refreshStatus()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            refreshStatus()
        }
    }

    private var stateColor: Color {
        switch cloudManager.syncState {
        case .idle: return .green
        case .syncing: return .blue
        case .paused: return .orange
        case .error: return .red
        }
    }

    private func triggerManualSync() {
        isSyncing = true
        lastError = nil
        Task {
            await cloudManager.sync()
            refreshStatus()
            isSyncing = false
        }
    }

    private func refreshStatus() {
        Task {
            pendingCount = await syncQueue.getPendingUploadCount()
            lastError = cloudManager.currentError
        }
    }
}
