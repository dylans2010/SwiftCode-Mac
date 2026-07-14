import SwiftUI

enum SimulatorSidebarSelection: Hashable, Identifiable {
    case service(SimulatorServiceItem)
    case device(String)

    var id: String {
        switch self {
        case .service(let item): return "service_\(item.rawValue)"
        case .device(let udid): return "device_\(udid)"
        }
    }
}

enum SimulatorServiceItem: String, CaseIterable, Identifiable {
    case previews = "SwiftUI Previews"
    case deviceManager = "Device Registry"
    case runtimes = "SDK Runtimes"
    case dragDropDeploy = "Deploy App"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .previews: return "sparkles"
        case .deviceManager: return "macbook.and.iphone"
        case .runtimes: return "square.stack.3d.down.right"
        case .dragDropDeploy: return "square.and.arrow.down"
        }
    }

    var accentColor: Color {
        switch self {
        case .previews: return .purple
        case .deviceManager: return .blue
        case .runtimes: return .teal
        case .dragDropDeploy: return .orange
        }
    }
}

@MainActor
struct SimulatorSidebar: View {
    @Binding var selection: SimulatorSidebarSelection?
    @State private var manager = SimulatorManager.shared
    @State private var showingCreationSheet = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Services") {
                    ForEach(SimulatorServiceItem.allCases) { item in
                        NavigationLink(value: SimulatorSidebarSelection.service(item)) {
                            Label {
                                Text(item.rawValue)
                                    .font(.body)
                            } icon: {
                                Image(systemName: item.icon)
                                    .foregroundStyle(item.accentColor)
                            }
                        }
                        .tag(SimulatorSidebarSelection.service(item))
                    }
                }

                Section {
                    let bootedDevices = manager.devices.filter { $0.state == .booted }
                    if bootedDevices.isEmpty {
                        Text("No active devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    } else {
                        ForEach(bootedDevices) { device in
                            SimulatorDeviceCard(device: device, isSelected: isSelected(device))
                                .tag(SimulatorSidebarSelection.device(device.udid))
                        }
                    }
                } header: {
                    HStack {
                        Text("Active Devices")
                        Spacer()
                        Button {
                            showingCreationSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Add Custom Simulator")
                    }
                }

                Section("Offline Devices") {
                    let offlineDevices = manager.devices.filter { $0.state != .booted }
                    if offlineDevices.isEmpty {
                        Text("No offline devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    } else {
                        ForEach(offlineDevices) { device in
                            SimulatorDeviceCard(device: device, isSelected: isSelected(device))
                                .tag(SimulatorSidebarSelection.device(device.udid))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .simulatorWorkspaceEmbedded()
        .sheet(isPresented: $showingCreationSheet) {
            SimulatorCreationView()
        }
    }

    private func isSelected(_ device: SimulatorDevice) -> Bool {
        if case .device(let udid) = selection {
            return udid == device.udid
        }
        return false
    }
}
