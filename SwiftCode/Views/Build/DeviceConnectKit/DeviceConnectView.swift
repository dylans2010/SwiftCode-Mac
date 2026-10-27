import SwiftUI

public struct DeviceConnectView: View {
    @State private var sidebarSelection = "dashboard"
    @State private var deviceManager = DeviceManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Elegant Unified Top Header
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.15))
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("DeviceConnect")
                            .font(.headline)
                        Text("Target Deployment & Simulator Hub")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Section Segmented Control
                Picker("", selection: $sidebarSelection) {
                    Text("Dashboard").tag("dashboard")
                    Text("Inspector").tag("inspector")
                    Text("Sessions").tag("sessions")
                    Text("Environment").tag("environment")
                    Text("Settings").tag("settings")
                }
                .pickerStyle(.segmented)
                .frame(width: 440)

                Spacer()

                // Target Device Quick Selector in Header
                HStack(spacing: 8) {
                    Circle()
                        .fill(deviceManager.selectedDevice != nil ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)

                    if deviceManager.devices.isEmpty {
                        Text(deviceManager.isDiscovering ? "Searching devices..." : "No devices connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("", selection: Binding(
                            get: { deviceManager.selectedDevice },
                            set: { newDevice in
                                if let dev = newDevice {
                                    deviceManager.selectDevice(dev)
                                }
                            }
                        )) {
                            ForEach(deviceManager.devices) { device in
                                Text("\(device.name) (\(device.model))")
                                    .tag(device as ConnectedDevice?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 180)
                    }

                    Button {
                        Task {
                            await deviceManager.refreshDevices()
                        }
                    } label: {
                        if deviceManager.isDiscovering {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Rescan connected devices & simulators")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .liquidGlass(style: .standard, cornerRadius: 0)

            Divider()

            // Dynamic Content
            ScrollView {
                VStack(spacing: 0) {
                    switch sidebarSelection {
                    case "dashboard":
                        DeviceConnectDeploymentView()
                    case "inspector":
                        DeviceConnectInspector()
                    case "sessions":
                        DeviceConnectSessionsView()
                    case "environment":
                        DeviceConnectEnvironmentView()
                    case "settings":
                        DeviceConnectSettingsView()
                    default:
                        DeviceConnectDeploymentView()
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: Bindable(XcodeBuildAPI.shared).showProjectGenerationUI) {
            BuildingXcodeProject()
        }
        .onAppear {
            Task {
                await deviceManager.startDiscovery()
            }
        }
        .onDisappear {
            Task {
                await deviceManager.stopDiscovery()
            }
        }
    }
}
