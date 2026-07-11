import SwiftUI

/// Search-friendly macOS grouped layout list to filter and inspect physical Simulator profiles.
public struct DeviceManagementView: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    @State private var searchQuery = ""

    public var body: some View {
        VStack(spacing: 0) {
            // Search Box Header
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter Devices...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                Spacer()

                Button(action: {
                    Task {
                        await simulatorManager.refresh()
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            let filteredDevices = simulatorManager.devices.filter {
                searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(searchQuery) || $0.state.rawValue.localizedCaseInsensitiveContains(searchQuery)
            }

            if filteredDevices.isEmpty {
                ContentUnavailableView {
                    Label("No Devices Match Filter", systemImage: "iphone.circle")
                } description: {
                    Text("Try typing another device type name or clean your query.")
                }
            } else {
                List {
                    ForEach(filteredDevices) { device in
                        HStack {
                            Image(systemName: device.state == .booted ? "iphone.radiowaves.left.and.right" : "iphone")
                                .font(.title3)
                                .foregroundStyle(device.state == .booted ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name)
                                    .font(.headline)
                                Text(device.udid)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Controls
                            HStack(spacing: 12) {
                                Text(device.state.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(device.state == .booted ? .green : .secondary)

                                if device.state == .shutdown {
                                    Button("Boot") {
                                        Task {
                                            await simulatorManager.bootDevice(udid: device.udid)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button("Shut Down") {
                                        Task {
                                            await simulatorManager.shutdownDevice(udid: device.udid)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
