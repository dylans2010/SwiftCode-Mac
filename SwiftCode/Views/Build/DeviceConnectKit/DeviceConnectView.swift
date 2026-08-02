import SwiftUI

public struct DeviceConnectView: View {
    @State private var sidebarSelection = "dashboard"
    @State private var deviceManager = DeviceManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Platform / Section Picker
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("DeviceConnect Workspace", systemImage: "macpro.gen3.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            Picker("Section", selection: $sidebarSelection) {
                                Text("Dashboard").tag("dashboard")
                                Text("Inspector").tag("inspector")
                                Text("Sessions").tag("sessions")
                                Text("Environment").tag("environment")
                                Text("Settings").tag("settings")
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // 2. Target Device GroupBox
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Selected Target Device", systemImage: "iphone")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                                if deviceManager.isDiscovering {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Button(action: {
                                        Task {
                                            await deviceManager.refreshDevices()
                                        }
                                    }) {
                                        Label("Refresh", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            if deviceManager.devices.isEmpty {
                                Text("No target devices discovered. Ensure your iOS device/Simulator is connected.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Picker("Device Selection", selection: Binding(
                                    get: { deviceManager.selectedDevice },
                                    set: { newDevice in
                                        if let dev = newDevice {
                                            deviceManager.selectDevice(dev)
                                        }
                                    }
                                )) {
                                    ForEach(deviceManager.devices) { device in
                                        Text("\(device.name) (\(device.model) • OS \(device.osVersion))")
                                            .tag(device as ConnectedDevice?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // 3. Dynamic Section Content
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
                }
                .padding(24)
            }
            .navigationTitle("DeviceConnect")
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
