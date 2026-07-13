import SwiftUI
import AppKit

@MainActor
struct SimulatorCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = SimulatorManager.shared

    @State private var deviceName = ""
    @State private var selectedDeviceType = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
    @State private var selectedRuntime = ""
    @State private var isCreating = false
    @State private var showingDiagnostics = false

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
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Create New Simulator", systemImage: "iphone.badge.play")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    // Card 1: Device Configuration
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Device Specifications", systemImage: "iphone.badge.play")
                                    .font(.subheadline.bold())
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

                    // Card 2: Target SDK Runtime Picker (The 4-State UI)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Target SDK Runtime", systemImage: "square.stack.3d.down.right.fill")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                runtimePickerStateView
                            }

                            Divider()
                                .padding(.vertical, 4)

                            RuntimeDiscoveryView(selectedRuntimeIdentifier: $selectedRuntime)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }

            // Footer Actions
            HStack {
                Spacer()
                Button("Create Device") {
                    createDevice()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedRuntime.isEmpty || isCreating)
            }
            .padding(.top, 16)
        }
        .simulatorWorkspaceEmbedded()
        .frame(width: 500, height: 600)
        .onAppear {
            initializeRuntimeSelection()
        }
        .onChange(of: manager.runtimes) {
            if selectedRuntime.isEmpty, let first = manager.runtimes.first {
                selectedRuntime = first.identifier
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            SimulatorDiagnosticsView()
        }
    }

    @ViewBuilder
    private var runtimePickerStateView: some View {
        switch manager.state {
        case .idle:
            Text("Subsystem idle...")
                .foregroundColor(.secondary)

        case .discovering(let stage):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading simulator runtimes")
                    Text(stage.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)

        case .loaded:
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

        case .empty(let reason):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("No simulator runtimes available.")
                        .font(.subheadline.bold())
                }

                Text(reason.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
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

                    Button("Diagnostics") {
                        showingDiagnostics = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(8)

        case .failed(let error):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(.red)
                    Text("Discovery Failed")
                        .font(.subheadline.bold())
                }

                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Retry") {
                        Task { await manager.refreshAll() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Show Diagnostics") {
                        showingDiagnostics = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Copy Error") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(error.localizedDescription, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(10)
            .background(Color.red.opacity(0.08))
            .cornerRadius(8)
        }
    }

    private func initializeRuntimeSelection() {
        if let firstRuntime = manager.runtimes.first {
            selectedRuntime = firstRuntime.identifier
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
