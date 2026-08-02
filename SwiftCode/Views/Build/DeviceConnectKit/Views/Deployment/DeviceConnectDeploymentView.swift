import SwiftUI

public struct DeviceConnectDeploymentView: View {
    @State private var deviceManager = DeviceManager.shared
    @State private var deploymentManager = DeploymentManager.shared
    @State private var buildManager = BuildManager.shared
    @State private var runtimeManager = RuntimeManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Overview Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deployment Dashboard")
                            .font(.title2.weight(.bold))
                        Text("Build, install, and run applications on linked developer targets.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if deploymentManager.isDeploying {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                // 2. Active Device Card
                if let device = deviceManager.selectedDevice {
                    GroupBox(label: Label("Selected Target Device", systemImage: "iphone")) {
                        HStack(spacing: 16) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name)
                                    .font(.headline)
                                Text("\(device.model) • iOS \(device.osVersion) (\(device.buildVersion))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    DeviceStatusBadge(status: device.isConnected ? "Connected" : "Disconnected")
                                    DeviceStatusBadge(status: device.isWireless ? "Wireless" : "USB")
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                } else {
                    ContentUnavailableView(
                        "No Target Device",
                        systemImage: "iphone.slash",
                        description: Text("Please select a target device from the sidebar to begin building or deploying.")
                    )
                }

                // 3. Deployment Pipeline Timeline Progress
                GroupBox(label: Label("Deployment Timeline", systemImage: "arrow.triangle.2.circlepath")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Pipeline Status:")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            DeviceStatusBadge(status: deploymentManager.deploymentStatus.description)
                        }

                        Text(deploymentManager.currentStageDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        // Render sequential milestones with checkboxes or indicators
                        VStack(alignment: .leading, spacing: 8) {
                            MilestoneRow(title: "Save Project Changes", isCompleted: deploymentManager.deploymentStatus != .idle)
                            MilestoneRow(title: "Validate Environment", isCompleted: deploymentManager.deploymentStatus != .idle && deploymentManager.deploymentStatus != .savingProject)
                            MilestoneRow(title: "Build Source Code", isCompleted: deploymentManager.deploymentStatus == .installingApplication || deploymentManager.deploymentStatus == .launchingApplication || deploymentManager.deploymentStatus == .running || deploymentManager.deploymentStatus == .completed)
                            MilestoneRow(title: "Install App Package", isCompleted: deploymentManager.deploymentStatus == .launchingApplication || deploymentManager.deploymentStatus == .running || deploymentManager.deploymentStatus == .completed)
                            MilestoneRow(title: "Launch & Stream Syslog", isCompleted: deploymentManager.deploymentStatus == .running || deploymentManager.deploymentStatus == .completed)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 4. Console output peek
                GroupBox(label: Label("Deployment Terminal Logs", systemImage: "terminal")) {
                    DeviceConnectConsole()
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding()
        }
    }
}

struct MilestoneRow: View {
    let title: String
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isCompleted ? .green : .secondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isCompleted ? .primary : .secondary)
            Spacer()
        }
    }
}
