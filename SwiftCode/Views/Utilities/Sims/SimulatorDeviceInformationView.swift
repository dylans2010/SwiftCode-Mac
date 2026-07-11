import SwiftUI

/// Detailed parameters and actions interface for the selected Simulator.
public struct SimulatorDeviceInformationView: View {
    @Environment(SimulatorManager.self) private var simulatorManager

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let device = simulatorManager.selectedDevice {
                    // Information Box
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Device Information", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                Spacer()
                            }

                            VStack(spacing: 10) {
                                infoRow(title: "Device Name", value: device.name)
                                infoRow(title: "UDID", value: device.udid, isMonospaced: true)
                                infoRow(title: "Status", value: device.state.rawValue, color: device.state == .booted ? .green : .secondary)
                                infoRow(title: "Runtime ID", value: device.runtimeIdentifier ?? "Unknown", isMonospaced: true)
                                infoRow(title: "Architecture", value: "arm64 (macOS Native)")
                                infoRow(title: "Availability", value: device.isAvailable ? "Available" : "Not Available", color: device.isAvailable ? .green : .red)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Action Controls Block
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Quick Actions", systemImage: "play.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Spacer()
                            }

                            SimulatorActionsView(device: device)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Installed Applications Block
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Deployed Applications", systemImage: "app.badge.fill")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                Spacer()
                            }

                            SimulatorAppsView(device: device)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                } else {
                    ContentUnavailableView {
                        Label("No Device Selected", systemImage: "iphone")
                    } description: {
                        Text("Select a device in the sidebar to view metrics.")
                    }
                }
            }
            .padding(24)
        }
    }

    private func infoRow(title: String, value: String, isMonospaced: Bool = false, color: Color = .primary) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(color)
                .font(isMonospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
        }
    }
}
