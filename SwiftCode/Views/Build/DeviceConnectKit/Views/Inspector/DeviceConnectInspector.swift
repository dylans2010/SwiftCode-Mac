import SwiftUI

public struct DeviceConnectInspector: View {
    @State private var deviceManager = DeviceManager.shared
    @State private var runtimeManager = RuntimeManager.shared
    @State private var signingManager = SigningManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let device = deviceManager.selectedDevice {
                    // Title
                    HStack {
                        Image(systemName: "iphone")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.title3.weight(.bold))
                            Text(device.model)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top)

                    Divider()

                    // General
                    VStack(alignment: .leading, spacing: 8) {
                        DeviceConnectHeader(title: "Hardware Specifications", systemImage: "cpu")
                        Group {
                            InspectorRow(label: "Platform", value: device.platform)
                            InspectorRow(label: "OS Version", value: device.osVersion)
                            InspectorRow(label: "Build Version", value: device.buildVersion)
                            InspectorRow(label: "Architecture", value: device.architecture)
                            InspectorRow(label: "UDID", value: device.udid)
                        }
                    }

                    Divider()

                    // Connection
                    VStack(alignment: .leading, spacing: 8) {
                        DeviceConnectHeader(title: "Connection Details", systemImage: "cable.connector")
                        Group {
                            InspectorRow(label: "Status", value: device.isConnected ? "Connected" : "Disconnected")
                            InspectorRow(label: "Transport", value: device.isWireless ? "Wireless Wi-Fi" : "USB Connection")
                            InspectorRow(label: "Deployment", value: device.isDeploymentSupported ? "Supported" : "Unsupported")
                        }
                    }

                    Divider()

                    // Runtime metrics
                    VStack(alignment: .leading, spacing: 8) {
                        DeviceConnectHeader(title: "Performance Metrics", systemImage: "chart.bar.xaxis")
                        Group {
                            InspectorRow(label: "CPU Usage", value: String(format: "%.1f%%", runtimeManager.metrics.cpuUsage))
                            InspectorRow(label: "Active Memory", value: String(format: "%.1f MB", runtimeManager.metrics.memoryUsage))
                            InspectorRow(label: "Active Threads", value: "\(runtimeManager.metrics.activeThreads)")
                        }
                    }

                    Divider()

                    // Signing Status
                    VStack(alignment: .leading, spacing: 8) {
                        DeviceConnectHeader(title: "Signing Security", systemImage: "key.fill")
                        InspectorRow(label: "Signing Status", value: signingManager.signingStatus.description)
                        if !signingManager.availableIdentities.isEmpty {
                            Text("Identities discovered: \(signingManager.availableIdentities.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "info.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No Device Selected")
                            .font(.headline)
                        Text("Connect or select an Apple hardware target to inspect detail parameters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
        }
        .frame(minWidth: 260, maxWidth: .infinity)
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
