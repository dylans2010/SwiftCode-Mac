import SwiftUI

/// Sidebar component for category selection and device navigation.
public struct SimulatorSidebar: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    @Binding public var selectedTab: SimulatorSidebarTab?
    @Binding public var selectedDeviceID: String?

    public var body: some View {
        VStack(spacing: 0) {
            // Header Title
            HStack {
                Label("Simulator Manager", systemImage: "macwindow.on.rectangle")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    Task {
                        await simulatorManager.refresh()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh Devices")
            }
            .padding()

            Divider()

            // Sidebar Categories
            List(selection: $selectedTab) {
                Section("Toolbox") {
                    ForEach(SimulatorSidebarTab.allCases) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.rawValue, systemImage: tab.iconName)
                        }
                        .tag(tab)
                    }
                }

                if selectedTab == .devices {
                    Section("Devices") {
                        if simulatorManager.devices.isEmpty {
                            Text("No devices found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(simulatorManager.devices) { device in
                                HStack {
                                    Image(systemName: device.state == .booted ? "iphone.radiowaves.left.and.right" : "iphone")
                                        .foregroundStyle(device.state == .booted ? .green : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.body)
                                            .fontWeight(selectedDeviceID == device.udid ? .semibold : .regular)
                                        Text(device.state.rawValue)
                                            .font(.caption2)
                                            .foregroundStyle(device.state == .booted ? .green : .secondary)
                                    }
                                    Spacer()
                                    if device.state == .booted {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedDeviceID = device.udid
                                    simulatorManager.selectedDeviceID = device.udid
                                }
                                .tag(device.udid)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}
