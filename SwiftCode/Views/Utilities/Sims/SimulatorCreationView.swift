import SwiftUI

struct SimulatorCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = SimulatorManager.shared

    @State private var deviceName = ""
    @State private var selectedDeviceType = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
    @State private var selectedRuntime = ""
    @State private var isCreating = false

    private let deviceTypes = [
        ("iPhone 16 Pro", "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"),
        ("iPhone 16", "com.apple.CoreSimulator.SimDeviceType.iPhone-16"),
        ("iPad Pro 13-inch (M4)", "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4"),
        ("Apple Vision Pro", "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro"),
        ("Apple Watch Series 10", "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create New Simulator")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))

            Form {
                Section {
                    TextField("Simulator Name", text: $deviceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                    Picker("Device Template", selection: $selectedDeviceType) {
                        ForEach(deviceTypes, id: \.1) { item in
                            Text(item.0).tag(item.1)
                        }
                    }

                    Picker("Target SDK Runtime OS", selection: $selectedRuntime) {
                        if manager.runtimes.isEmpty {
                            Text("No Runtimes Available").tag("")
                        } else {
                            ForEach(manager.runtimes) { runtime in
                                Text(runtime.name).tag(runtime.identifier)
                            }
                        }
                    }
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(action: createDevice) {
                    if isCreating {
                        ProgressView().scaleEffect(0.5).frame(width: 40)
                    } else {
                        Text("Create Device")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedRuntime.isEmpty || isCreating)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
        }
        .frame(width: 480, height: 320)
        .onAppear {
            if let firstRuntime = manager.runtimes.first {
                selectedRuntime = firstRuntime.identifier
            }
        }
    }

    private func createDevice() {
        isCreating = true
        Task {
            await manager.createNewDevice(name: deviceName, deviceType: selectedDeviceType, runtime: selectedRuntime)
            isCreating = false
            dismiss()
        }
    }
}
