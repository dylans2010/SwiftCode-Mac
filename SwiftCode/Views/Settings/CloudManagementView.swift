import SwiftUI

@Observable
@MainActor
class CloudManagementState {
    var syncEnabled: Bool = true
    var activeProvider: CloudProviderType = .supabase {
        didSet {
            UserDefaults.standard.set(activeProvider.rawValue, forKey: "com.swiftcode.cloud.active_provider")
        }
    }
    var syncInProgress: Bool = false
    var lastSyncDate: Date? = Date()
    var syncProgress: Double = 0.0
    var recentErrors: [String] = []

    init() {
        if let raw = UserDefaults.standard.string(forKey: "com.swiftcode.cloud.active_provider"),
           let type = CloudProviderType(rawValue: raw) {
            self.activeProvider = type
        }
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
                            Text("Storage Used:")
                            Spacer()
                            Text("14.5 MB")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Connected Devices:")
                            Spacer()
                            Text("3 Active")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }

                // Sync Trigger Actions
                HStack(spacing: 16) {
                    Button(action: {
                        Task {
                            state.syncInProgress = true
                            state.syncProgress = 0.1
                            for step in 1...10 {
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                state.syncProgress = Double(step) / 10.0
                            }
                            state.lastSyncDate = Date()
                            state.syncInProgress = false
                        }
                    }) {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.syncInProgress)

                    Button(action: {
                        state.syncInProgress = false
                        state.syncProgress = 0.0
                    }) {
                        Label("Pause Syncing", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
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
