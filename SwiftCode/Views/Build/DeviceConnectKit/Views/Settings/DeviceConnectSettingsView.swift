import SwiftUI

public struct DeviceConnectSettingsView: View {
    @Bindable private var prefs = PreferencesManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Automation Controls", systemImage: "bolt.ring.closed")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Automatically Discover Connected Devices", isOn: $prefs.autoDiscover)
                        Toggle("Auto-Validate Environment on Open", isOn: $prefs.autoValidate)
                        Toggle("Automatically Save Editor state before Deployment", isOn: $prefs.autoSaveBeforeDeploy)
                        Toggle("Automatically Launch Application post Successful Install", isOn: $prefs.autoLaunch)
                        Toggle("Automatically stream Runtime Syslog Console on run", isOn: $prefs.autoStreamLogs)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Log & History Retention", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Spacer()
                    }

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
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }
}
