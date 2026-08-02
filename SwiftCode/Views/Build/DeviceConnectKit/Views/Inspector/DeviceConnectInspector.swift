import SwiftUI

public struct DeviceConnectInspector: View {
    @State private var deviceManager = DeviceManager.shared
    @State private var runtimeManager = DeviceConnectRuntimeManager.shared
    @State private var signingManager = SigningManager.shared

    public init() {}

    public var body: some View {
        if let device = deviceManager.selectedDevice {
            VStack(spacing: 24) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Hardware Specifications", systemImage: "cpu")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        VStack(spacing: 8) {
                            InspectorRow(label: "Name", value: device.name)
                            InspectorRow(label: "Model", value: device.model)
                            InspectorRow(label: "Platform", value: device.platform)
                            InspectorRow(label: "OS Version", value: device.osVersion)
                            InspectorRow(label: "Build Version", value: device.buildVersion)
                            InspectorRow(label: "Architecture", value: device.architecture)
                            InspectorRow(label: "UDID", value: device.udid)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Connection Details", systemImage: "cable.connector")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        VStack(spacing: 8) {
                            InspectorRow(label: "Status", value: device.isConnected ? "Connected" : "Disconnected")
                            InspectorRow(label: "Transport", value: device.isWireless ? "Wireless Wi-Fi" : "USB Connection")
                            InspectorRow(label: "Deployment", value: device.isDeploymentSupported ? "Supported" : "Unsupported")
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Performance Metrics", systemImage: "chart.bar.xaxis")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        VStack(spacing: 8) {
                            InspectorRow(label: "CPU Usage", value: String(format: "%.1f%%", runtimeManager.metrics.cpuUsage))
                            InspectorRow(label: "Active Memory", value: String(format: "%.1f MB", runtimeManager.metrics.memoryUsage))
                            InspectorRow(label: "Active Threads", value: "\(runtimeManager.metrics.activeThreads)")
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Signing Security", systemImage: "key.fill")
                                .font(.headline)
                                .foregroundColor(.red)
                            Spacer()
                        }

                        VStack(spacing: 8) {
                            InspectorRow(label: "Signing Status", value: signingManager.signingStatus.description)
                            if !signingManager.availableIdentities.isEmpty {
                                InspectorRow(label: "Identities discovered", value: "\(signingManager.availableIdentities.count)")
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        } else {
            GroupBox {
                VStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Device Selected")
                        .font(.headline)
                    Text("Connect or select an Apple hardware target to inspect detail parameters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }
}

struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
