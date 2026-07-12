import SwiftUI

struct SimulatorSettingsView: View {
    @State private var manager = SimulatorManager.shared

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Subsystem Settings", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()
                }

                Divider()

                Form {
                    Picker("Default Device Layout Orientation", selection: $manager.configuration.preferredOrientation) {
                        Text("Portrait").tag("Portrait")
                        Text("Landscape").tag("Landscape")
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()

                    Toggle("Automatically Sync Hardware Keyboard Input", isOn: $manager.configuration.connectHardwareKeyboard)

                    Toggle("Display Frame Rate (FPS) Performance Counter", isOn: $manager.configuration.showFrameRateCounter)

                    Picker("Default Runtime Architecture Profile", selection: $manager.configuration.defaultRuntimePlatform) {
                        Text("iOS").tag("iOS")
                        Text("watchOS").tag("watchOS")
                        Text("tvOS").tag("tvOS")
                        Text("visionOS").tag("visionOS")
                    }

                    TextField("Max Console Output Buffer Limit (Lines)", value: $manager.configuration.maxConsoleLogLines, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}
