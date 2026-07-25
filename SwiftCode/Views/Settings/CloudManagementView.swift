import SwiftUI
import Observation

@Observable
@MainActor
class CloudManagementState {
    var syncEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "com.swiftcode.cloud.sync_enabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "com.swiftcode.cloud.sync_enabled")
            if newValue {
                Task {
                    await CloudSyncEngineImpl.shared.resume()
                }
            } else {
                Task {
                    await CloudSyncEngineImpl.shared.pause()
                }
            }
        }
    }

    var activeProvider: CloudProviderType {
        get {
            let raw = UserDefaults.standard.string(forKey: "com.swiftcode.cloud.active_provider") ?? "None"
            return CloudProviderType(rawValue: raw) ?? .supabase
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "com.swiftcode.cloud.active_provider")
            Task {
                try? await CloudSyncEngineImpl.shared.triggerSync()
            }
        }
    }

    var syncInProgress: Bool {
        CloudSyncEngineImpl.shared.syncState == .syncing
    }

    var lastSyncDate: Date? {
        CloudSyncEngineImpl.shared.lastSyncTime
    }

    var syncProgress: Double {
        CloudSyncEngineImpl.shared.syncProgress
    }

    var pendingTransactionsCount: Int = 0

    init() {}

    func refreshPendingTransactionsCount() async {
        let pending = await UploadQueue.shared.getPending()
        self.pendingTransactionsCount = pending.count
    }
}

public struct CloudManagementView: View {
    @State private var state = CloudManagementState()
    @State private var showSupabaseDetails = false
    @State private var showICloudDetails = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // General Cloud Sync Toggle
            GroupBox(label: Label("General Cloud Syncing", systemImage: "icloud.and.arrow.up.fill")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Automated Cloud Syncing", isOn: $state.syncEnabled)
                        .toggleStyle(.checkbox)
                        .font(.body)

                    Text("When active, all local projects, workspace states, AI chats, and editor styles automatically sync across all your devices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            if state.syncEnabled {
                // Provider Selection
                GroupBox(label: Label("Preferred Cloud Provider", systemImage: "network")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Provider:", selection: $state.activeProvider) {
                            Text("SwiftCode Cloud (Supabase)").tag(CloudProviderType.supabase)
                            Text("Apple iCloud").tag(CloudProviderType.icloud)
                        }
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()

                        Text("Only one provider may be active at a time. Switching providers will securely migrate or merge your existing data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            if state.activeProvider == .supabase {
                                Button("Open Supabase Sync Panel...") {
                                    showSupabaseDetails = true
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button("Open iCloud Sync Panel...") {
                                    showICloudDetails = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(8)
                }

                // Status & Performance Statistics
                GroupBox(label: Label("Sync Status & Metrics", systemImage: "chart.bar.doc.horizontal")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Sync State:")
                            Spacer()
                            if state.syncInProgress {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 16, height: 16)
                                Text("Synchronizing... (\(Int(state.syncProgress * 100))%)")
                                    .foregroundStyle(.blue)
                            } else if CloudSyncEngineImpl.shared.syncState == .error {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("Sync Connection Offline")
                                    .bold()
                                    .foregroundStyle(.red)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Fully Synchronized")
                                    .bold()
                            }
                        }

                        Divider()

                        HStack {
                            Text("Last Successful Sync:")
                            Spacer()
                            if let lastSync = state.lastSyncDate {
                                Text(lastSync, style: .time)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Never")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Text("Active Table Sync Metrics:")
                            Spacer()
                            Text("projects, settings, snippets, chat_history")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Pending Sync Transactions:")
                            Spacer()
                            Text("\(state.pendingTransactionsCount) Operations")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }

                // Sync Trigger Actions
                HStack(spacing: 16) {
                    Button(action: {
                        Task {
                            try? await CloudSyncEngineImpl.shared.triggerSync()
                            await state.refreshPendingTransactionsCount()
                        }
                    }) {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.syncInProgress)

                    Button(action: {
                        Task {
                            await CloudSyncEngineImpl.shared.pause()
                        }
                    }) {
                        Label("Pause Syncing", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(CloudSyncEngineImpl.shared.syncState == .paused)

                    Spacer()
                }
            }
        }
        .onAppear {
            Task {
                await state.refreshPendingTransactionsCount()
            }
        }
        .sheet(isPresented: $showSupabaseDetails) {
            SupabaseCloudView()
                .frame(width: 650, height: 500)
        }
        .sheet(isPresented: $showICloudDetails) {
            ICloudCloudView()
                .frame(width: 650, height: 500)
        }
    }
}
