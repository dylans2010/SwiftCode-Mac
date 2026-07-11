import SwiftUI

/// Form modal triggering creation of new Simulator hardware profiles.
public struct SimulatorCreationView: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    @Environment(\.dismiss) private var dismiss

    @State private var deviceName = "My New Simulator"
    @State private var selectedDeviceType = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
    @State private var selectedRuntime = "com.apple.CoreSimulator.SimRuntime.iOS-18-0"

    private let deviceTypes = [
        ("iPhone 16", "com.apple.CoreSimulator.SimDeviceType.iPhone-16"),
        ("iPhone 16 Pro", "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"),
        ("iPhone 15", "com.apple.CoreSimulator.SimDeviceType.iPhone-15"),
        ("iPad Pro (13-inch) (M4)", "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4"),
        ("Apple Watch Series 10", "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10"),
        ("Apple Vision Pro", "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro")
    ]

    public var body: some View {
        NavigationStack {
            Form {
                Section("Properties") {
                    TextField("Name", text: $deviceName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }

                Section("Hardware & OS") {
                    Picker("Device Type", selection: $selectedDeviceType) {
                        ForEach(deviceTypes, id: \.1) { name, id in
                            Text(name).tag(id)
                        }
                    }

                    Picker("OS Runtime", selection: $selectedRuntime) {
                        if simulatorManager.runtimes.isEmpty {
                            Text("iOS 18.0 (Simulated)").tag("com.apple.CoreSimulator.SimRuntime.iOS-18-0")
                        } else {
                            ForEach(simulatorManager.runtimes) { runtime in
                                Text(runtime.name).tag(runtime.identifier)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Simulator")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await simulatorManager.createDevice(
                                name: deviceName,
                                deviceType: selectedDeviceType,
                                runtime: selectedRuntime
                            )
                            dismiss()
                        }
                    }
                    .disabled(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
