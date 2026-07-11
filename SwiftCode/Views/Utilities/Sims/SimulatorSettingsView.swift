import SwiftUI

/// Form layout permitting configuration of local simctl paths and update loops.
public struct SimulatorSettingsView: View {
    @State private var config = SimulatorConfiguration.default
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            Form {
                Section("Developer Options") {
                    TextField("Custom simctl Path", text: Binding(
                        get: { config.customSimctlPath ?? "" },
                        set: { config.customSimctlPath = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .help("Specify custom developer tools directory if not automatically resolved by xcrun.")

                    Toggle("Enable Verbose Logging", isOn: $config.verboseLogging)
                        .help("Write complete simctl standard error outputs into Diagnostics Console.")

                    Toggle("Auto Open Simulator.app on Boot", isOn: $config.autoOpenSimulatorApp)
                        .help("Instantly launch Apple's native Simulator.app container when booting devices.")
                }

                Section("Observation Loop") {
                    Slider(value: $config.updateIntervalSeconds, in: 2.0...30.0, step: 1.0) {
                        Text("Refresh Rate: \(Int(config.updateIntervalSeconds))s")
                    }
                    .help("Interval between scanning background simulator processes.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Simulator Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Persist config overrides here
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 450, height: 320)
    }
}
