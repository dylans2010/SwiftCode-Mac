import SwiftUI

struct SimulatorSidebar: View {
    @State private var manager = SimulatorManager.shared
    @State private var showingCreationSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Devices")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()

                Button {
                    showingCreationSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Add Custom Simulator")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            List(selection: Bindable(manager).selectedDeviceID) {
                Section("Active Simulators") {
                    let bootedDevices = manager.devices.filter { $0.state == .booted }
                    if bootedDevices.isEmpty {
                        Text("No active devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    } else {
                        ForEach(bootedDevices) { device in
                            SimulatorDeviceCard(device: device, isSelected: manager.selectedDeviceID == device.udid)
                                .tag(device.udid)
                        }
                    }
                }

                Section("Offline Simulators") {
                    let offlineDevices = manager.devices.filter { $0.state != .booted }
                    if offlineDevices.isEmpty {
                        Text("No offline devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    } else {
                        ForEach(offlineDevices) { device in
                            SimulatorDeviceCard(device: device, isSelected: manager.selectedDeviceID == device.udid)
                                .tag(device.udid)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(isPresented: $showingCreationSheet) {
            SimulatorCreationView()
        }
    }
}
