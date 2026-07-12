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

    var groupedRuntimes: [String: [SimulatorRuntime]] {
        Dictionary(grouping: manager.runtimes, by: { $0.platform })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Card 1: Configuration Fields
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Device Specifications", systemImage: "iphone.badge.play")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Simulator Name")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("Enter custom name", text: $deviceName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Device Template")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Picker("Device Template", selection: $selectedDeviceType) {
                                    ForEach(deviceTypes, id: \.1) { item in
                                        Text(item.0).tag(item.1)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Runtime SDK Picker with multiple states
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Target SDK Runtime", systemImage: "square.stack.3d.down.right.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                if manager.isRefreshing {
                                    // Loading State
                                    HStack(spacing: 12) {
                                        ProgressView().controlSize(.small)
                                        Text("Discovering installed runtimes...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                } else if let diag = manager.pipelineDiagnostics, !diag.isSimctlAvailable {
                                    // Failure State
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label("Unable to discover simulator runtimes.", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption.bold())
                                            .foregroundColor(.red)

                                        HStack(spacing: 8) {
                                            Button("Retry") {
                                                Task { await manager.refreshAll() }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Button("Show Diagnostics") {
                                                // Handle diagnostics presentation
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Button("Copy Error") {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(diag.latestStderr, forType: .string)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                                } else if manager.runtimes.isEmpty {
                                    // Empty State
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label("No simulator runtimes are installed.", systemImage: "opticaldisc.fill")
                                            .font(.caption.bold())
                                            .foregroundColor(.orange)

                                        HStack(spacing: 8) {
                                            Button("Refresh") {
                                                Task { await manager.refreshAll() }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Button("Open Xcode Settings") {
                                                #if os(macOS)
                                                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app"))
                                                #endif
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(8)
                                } else {
                                    // Loaded State
                                    Picker("Target SDK Runtime OS", selection: $selectedRuntime) {
                                        ForEach(Array(groupedRuntimes.keys).sorted(), id: \.self) { platform in
                                            Section(header: Text(platform)) {
                                                ForEach(groupedRuntimes[platform] ?? []) { runtime in
                                                    Text(runtime.name).tag(runtime.identifier)
                                                }
                                            }
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Create New Simulator")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Device") {
                        createDevice()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedRuntime.isEmpty || isCreating)
                }
            }
        }
        .frame(width: 500, height: 420)
        .onAppear {
            if let firstRuntime = manager.runtimes.first {
                selectedRuntime = firstRuntime.identifier
            }
        }
        .onChange(of: manager.runtimes) { _, runtimes in
            if selectedRuntime.isEmpty, let first = runtimes.first {
                selectedRuntime = first.identifier
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
