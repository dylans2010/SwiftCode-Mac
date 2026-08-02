import SwiftUI

public struct DeviceConnectDeploymentView: View {
    @State private var deviceManager = DeviceManager.shared
    @State private var deploymentManager = DeploymentManager.shared
    @State private var buildManager = BuildManager.shared
    @State private var runtimeManager = DeviceConnectRuntimeManager.shared
    @State private var environmentManager = EnvironmentManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            // Action Box (Run, Stop, Clear)
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Deployment Actions", systemImage: "play.circle")
                            .font(.headline)
                            .foregroundColor(.green)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button(action: triggerDeploymentRun) {
                            HStack {
                                if deploymentManager.isDeploying {
                                    ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text("Run App")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(deviceManager.selectedDevice == nil || deploymentManager.isDeploying)

                        Button(action: stopDeploymentRun) {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("Stop App")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .foregroundColor(.red)
                        .disabled(deviceManager.selectedDevice == nil || (!deploymentManager.isDeploying && runtimeManager.runtimeStatus != .running))
                    }

                    if deviceManager.selectedDevice == nil {
                        Text("Please select or connect a target device first.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button(action: {
                        Task {
                            await environmentManager.clearDerivedData()
                        }
                    }) {
                        HStack {
                            if environmentManager.isDerivedDataClearing {
                                ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                            } else {
                                Image(systemName: "trash.slash")
                            }
                            Text("Clear DerivedData")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(environmentManager.isDerivedDataClearing)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Deployment Timeline progress
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Deployment Timeline", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Spacer()
                    }

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

                        // Render sequential milestones
                        VStack(alignment: .leading, spacing: 8) {
                            MilestoneRow(title: "Save Project Changes", isCompleted: deploymentManager.deploymentStatus != .idle)
                            MilestoneRow(title: "Validate Environment", isCompleted: deploymentManager.deploymentStatus != .idle && deploymentManager.deploymentStatus != .savingProject)
                            MilestoneRow(title: "Build Source Code", isCompleted: deploymentManager.deploymentStatus == .installingApplication || deploymentManager.deploymentStatus == .launchingApplication || deploymentManager.deploymentStatus == .running || deploymentManager.deploymentStatus == .completed)
                            MilestoneRow(title: "Install App Package", isCompleted: deploymentManager.deploymentStatus == .launchingApplication || deploymentManager.deploymentStatus == .running || deploymentManager.deploymentStatus == .completed)
                            MilestoneRow(title: "Launch & Stream Syslog", isCompleted: deploymentManager.deploymentStatus == .running || deploymentManager.deploymentStatus == .completed)
                        }
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Console output peek
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Deployment Terminal Logs", systemImage: "terminal")
                            .font(.headline)
                            .foregroundColor(.cyan)
                        Spacer()
                    }

                    DeviceConnectConsole()
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    private func triggerDeploymentRun() {
        guard let selected = deviceManager.selectedDevice else { return }
        Task {
            // Simulate typical parameters for deployment target
            await deploymentManager.startDeployment(
                device: selected,
                projectName: "SwiftCodeDemo",
                projectPath: "/tmp/SwiftCodeDemo.xcodeproj",
                scheme: "SwiftCodeDemo",
                appBundleURL: URL(fileURLWithPath: "/tmp/SwiftCodeDemo.app"),
                bundleIdentifier: "com.swiftcode.demo"
            )
        }
    }

    private func stopDeploymentRun() {
        guard let selected = deviceManager.selectedDevice else { return }
        Task {
            _ = try? await RuntimeService().stop(deviceUDID: selected.udid, bundleIdentifier: "com.swiftcode.demo")
            runtimeManager.stopMonitoring(deviceUDID: selected.udid)
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
