import SwiftUI

public struct DeviceConnectSettingsView: View {
    @Bindable private var prefs = PreferencesManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DeviceConnect Settings")
                        .font(.title2.weight(.bold))
                    Text("Configure deployment execution triggers and discovery preferences.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GroupBox(label: Label("Automation Actions", systemImage: "bolt.ring.closed")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Automatically Discover Connected Devices", isOn: $prefs.autoDiscover)
                        Toggle("Auto-Validate Environment on Open", isOn: $prefs.autoValidate)
                        Toggle("Automatically Save Editor state before Deployment", isOn: $prefs.autoSaveBeforeDeploy)
                        Toggle("Automatically Launch Application post Successful Install", isOn: $prefs.autoLaunch)
                        Toggle("Automatically stream Runtime Syslog Console on run", isOn: $prefs.autoStreamLogs)
                    }
                    .padding(.vertical, 8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Label("Log & History Retention", systemImage: "clock.arrow.circlepath")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Keep Deployment & Session history", isOn: $prefs.keepHistory)
                        HStack {
                            Text("Maximum Sessions in Memory:")
                            Spacer()
                            Picker("", selection: $prefs.maxSessionCount) {
                                Text("25").tag(25)
                                Text("50").tag(50)
                                Text("100").tag(100)
                                Text("Unlimited").tag(9999)
                            }
                            .frame(width: 120)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding()
        }
    }
}
