import SwiftUI

public struct VirtualizationPreferencesView: View {
    @State private var stateStore = VirtualizationStateStore.shared

    @State private var autoStart: Bool = false
    @State private var advancedStats: Bool = true
    @State private var defaultNetMode: String = "NAT"

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Virtualization Preferences")
                        .font(.system(size: 24, weight: .bold))
                    Text("Configure global service parameters for the internal hypervisor daemon and telemetry monitor.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Section 1: Console background behavior
                GroupBox(label:
                    Label("Console Behavior", systemImage: "macwindow")
                        .font(.headline)
                        .foregroundStyle(.blue)
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Auto-start hypervisor background agent on system startup", isOn: $autoStart)
                            .toggleStyle(.checkbox)
                        Text("Launches a lightweight background service task to handle sandbox container connections.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 18)

                        Divider()

                        Toggle("Stream live GPU & processor memory updates", isOn: $advancedStats)
                            .toggleStyle(.checkbox)
                        Text("Actively gathers background telemetry statistics of host impact from running sandboxes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 18)
                    }
                    .padding(.vertical, 6)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 2: Network options
                GroupBox(label:
                    Label("Network Connections", systemImage: "network")
                        .font(.headline)
                        .foregroundStyle(.purple)
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Default Socket Connection Protocol:")
                            .fontWeight(.medium)
                            .font(.subheadline)

                        Picker("", selection: $defaultNetMode) {
                            Text("NAT (Network Address Translation)").tag("NAT")
                            Text("Bridged Network Device Interface").tag("Bridge")
                            Text("Host-Only Isolated Private Subnet").tag("HostOnly")
                        }
                        .pickerStyle(.radioGroup)

                        Text("NAT is highly recommended; it allows guest environments to share your Mac's internet connection securely without exposing open ports to external networks.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                HStack {
                    Spacer()
                    Button("Save Preferences") {
                        savePrefs()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            autoStart = stateStore.preferenceAutoStartAgent
            advancedStats = stateStore.preferenceShowAdvancedStats
            defaultNetMode = stateStore.preferenceDefaultNetworkMode
        }
    }

    private func savePrefs() {
        stateStore.preferenceAutoStartAgent = autoStart
        stateStore.preferenceShowAdvancedStats = advancedStats
        stateStore.preferenceDefaultNetworkMode = defaultNetMode
        stateStore.addLog("Successfully saved global virtualization preferences.", type: .success)
    }
}
