import SwiftUI

@MainActor
struct SimulatorSettingsView: View {
    @State private var manager = SimulatorManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Subsystem Settings", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundColor(.blue)
                Spacer()
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Default Device Layout Orientation")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Picker("Default Device Layout Orientation", selection: $manager.configuration.preferredOrientation) {
                                    Text("Portrait").tag("Portrait")
                                    Text("Landscape").tag("Landscape")
                                }
                                .pickerStyle(.segmented)
                            }

                            Toggle("Automatically Sync Hardware Keyboard Input", isOn: $manager.configuration.connectHardwareKeyboard)

                            Toggle("Display Frame Rate (FPS) Performance Counter", isOn: $manager.configuration.showFrameRateCounter)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Default Runtime Architecture Profile")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Picker("Default Runtime Architecture Profile", selection: $manager.configuration.defaultRuntimePlatform) {
                                    Text("iOS").tag("iOS")
                                    Text("watchOS").tag("watchOS")
                                    Text("tvOS").tag("tvOS")
                                    Text("visionOS").tag("visionOS")
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Max Console Output Buffer Limit (Lines)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("Max Console Output Buffer Limit", value: $manager.configuration.maxConsoleLogLines, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 150)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
        }
        .simulatorWorkspaceEmbedded()
    }
}
