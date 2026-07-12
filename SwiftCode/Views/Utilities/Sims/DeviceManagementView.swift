import SwiftUI

struct DeviceManagementView: View {
    @State private var manager = SimulatorManager.shared
    @State private var showingCreationSheet = false
    @State private var showingDiagnosticsSheet = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Device Registry", systemImage: "macbook.and.iphone")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()

                    Button {
                        showingCreationSheet = true
                    } label: {
                        Label("Add Simulator", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        showingDiagnosticsSheet = true
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await manager.refreshAll()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                if manager.devices.isEmpty {
                    ContentUnavailableView {
                        Label("No Devices Discovered", systemImage: "iphone.slash")
                    } description: {
                        Text("Verify Xcode command line tools are installed or create a virtual device.")
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(manager.devices) { device in
                            HStack {
                                Image(systemName: "iphone")
                                    .font(.title3)
                                    .foregroundColor(device.state == .booted ? .green : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.subheadline.bold())
                                    Text(device.udid)
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(device.state.rawValue)
                                    .font(.caption)
                                    .foregroundColor(device.state == .booted ? .green : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(device.state == .booted ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                                    .cornerRadius(6)

                                Menu {
                                    if device.state != .booted {
                                        Button("Boot") {
                                            manager.selectedDeviceID = device.udid
                                            Task { await manager.bootSelectedDevice() }
                                        }
                                    } else {
                                        Button("Shutdown") {
                                            manager.selectedDeviceID = device.udid
                                            Task { await manager.shutdownSelectedDevice() }
                                        }
                                    }

                                    Button("Erase") {
                                        manager.selectedDeviceID = device.udid
                                        Task { await manager.eraseSelectedDevice() }
                                    }
                                    .disabled(device.state == .booted)

                                    Button("Delete", role: .destructive) {
                                        manager.selectedDeviceID = device.udid
                                        Task { await manager.deleteSelectedDevice() }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)

                            if device.id != manager.devices.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
        .sheet(isPresented: $showingCreationSheet) {
            SimulatorCreationView()
        }
        .sheet(isPresented: $showingDiagnosticsSheet) {
            SimulatorDiagnosticsView()
        }
    }
}
