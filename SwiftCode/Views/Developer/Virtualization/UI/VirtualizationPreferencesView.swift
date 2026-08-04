import SwiftUI

public struct VirtualizationPreferencesView: View {
    @State private var stateStore = VirtualizationStateStore.shared

    @State private var autoStart: Bool = false
    @State private var advancedStats: Bool = true
    @State private var defaultNetMode: String = "NAT"

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Virtualization Preferences")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Configure global settings for the internal hypervisor and developer console workspace.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                GroupBox(label: Text("Workspace Console Behavior").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-start virtualization background agent on system boot", isOn: $autoStart)
                            .toggleStyle(.checkbox)
                        Text("Launches a lightweight VM daemon task to handle active container services in the background.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 18)

                        Divider()
                            .padding(.vertical, 4)

                        Toggle("Stream live GPU & process telemetry updates", isOn: $advancedStats)
                            .toggleStyle(.checkbox)
                        Text("Gathers background statistics of host CPU and memory impact of active virtual machines.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 18)
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Text("Network & Port Mapping Protocols").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Default Connection Protocol:", selection: $defaultNetMode) {
                            Text("NAT (Network Address Translation)").tag("NAT")
                            Text("Bridged Network Device").tag("Bridge")
                            Text("Host-Only Isolated Subnet").tag("HostOnly")
                        }
                        .pickerStyle(.radioGroup)

                        Text("NAT (recommended) allows guest environments to share your macOS connection without exposing ports directly to local networks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                HStack {
                    Spacer()
                    Button("Save Preferences") {
                        savePrefs()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
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
        stateStore.addLog("Saved global virtualization preferences.", type: .success)
    }
}
