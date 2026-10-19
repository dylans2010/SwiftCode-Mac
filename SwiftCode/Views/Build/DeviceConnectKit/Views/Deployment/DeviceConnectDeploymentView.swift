import SwiftUI

public struct DeviceConnectDeploymentView: View {
    @State private var deviceManager = DeviceManager.shared
    @State private var deploymentManager = DeploymentManager.shared
    @State private var buildManager = BuildManager.shared
    @State private var runtimeManager = DeviceConnectRuntimeManager.shared
    @State private var environmentManager = EnvironmentManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // 1. Target Device Status Card
            targetDeviceCard

            // 2. Deployment Actions Toolbar Card
            actionsCard

            // 3. Deployment Pipeline Progress Card
            pipelineCard

            // 4. Deployment Terminal Logs Card
            logsCard
        }
    }

    // MARK: - Target Device Card
    private var targetDeviceCard: some View {
        HStack(spacing: 16) {
            if let device = deviceManager.selectedDevice {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.15))
                    Image(systemName: device.model.contains("iPad") ? "ipad" : "iphone")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(device.name)
                            .font(.headline)
                        Text(device.model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }

                    Text("iOS \(device.osVersion) • \(device.udid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Ready")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.1), in: Capsule())
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                    Image(systemName: "iphone.badge.play")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No Target Device Connected")
                        .font(.headline)
                    Text("Connect an iOS device via USB, or launch an iOS Simulator to build and deploy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        if let simURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator") {
                            NSWorkspace.shared.openApplication(at: simURL, configuration: NSWorkspace.OpenConfiguration())
                        }
                    } label: {
                        Label("Open Simulator", systemImage: "play.display")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await deviceManager.refreshDevices()
                        }
                    } label: {
                        Label("Scan Devices", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Actions Card
    private var actionsCard: some View {
        HStack(spacing: 12) {
            Button(action: triggerDeploymentRun) {
                HStack(spacing: 6) {
                    if deploymentManager.isDeploying {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text("Run App")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(deviceManager.selectedDevice == nil || deploymentManager.isDeploying)

            Button(action: stopDeploymentRun) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text("Stop App")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .foregroundColor(.red)
            .disabled(deviceManager.selectedDevice == nil || (!deploymentManager.isDeploying && runtimeManager.runtimeStatus != .running))

            Button(action: validateOrGenerateXcodeProject) {
                HStack(spacing: 6) {
                    Image(systemName: "hammer")
                    Text("Validate / Generate Project")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()

            Button(action: {
                Task {
                    await environmentManager.clearDerivedData()
                }
            }) {
                HStack(spacing: 6) {
                    if environmentManager.isDerivedDataClearing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text("Clear DerivedData")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(environmentManager.isDerivedDataClearing)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Pipeline Card
    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Deployment Pipeline", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                DeviceStatusBadge(status: deploymentManager.deploymentStatus.description)
            }

            if !deploymentManager.currentStageDescription.isEmpty {
                Text(deploymentManager.currentStageDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Milestone Stepper
            HStack(spacing: 8) {
                milestonePill(number: "1", title: "Save", isCompleted: deploymentManager.deploymentStatus != .idle)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                milestonePill(number: "2", title: "Validate", isCompleted: deploymentManager.deploymentStatus != .idle && deploymentManager.deploymentStatus != .savingProject)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                milestonePill(number: "3", title: "Build", isCompleted: deploymentManager.deploymentStatus == .installingApplication || deploymentManager.deploymentStatus == .launchingApplication || deploymentManager.deploymentStatus == .running || deploymentManager.deploymentStatus == .completed)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                milestonePill(number: "4", title: "Install", isCompleted: deploymentManager.deploymentStatus == .launchingApplication || deploymentManager.deploymentStatus == .running || deploymentManager.deploymentStatus == .completed)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                milestonePill(number: "5", title: "Launch", isCompleted: deploymentManager.deploymentStatus == .running || deploymentManager.deploymentStatus == .completed)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func milestonePill(number: String, title: String, isCompleted: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 18, height: 18)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text(number)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(title)
                .font(.caption.weight(isCompleted ? .semibold : .regular))
                .foregroundStyle(isCompleted ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            isCompleted ? Color.green.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.3),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Logs Card
    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Terminal & Console Logs", systemImage: "terminal")
                    .font(.headline)
                    .foregroundColor(.cyan)
                Spacer()
            }

            DeviceConnectConsole()
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func triggerDeploymentRun() {
        guard let selected = deviceManager.selectedDevice else { return }

        // Dynamically resolve everything from XcodeBuildAPI
        let api = XcodeBuildAPI.shared
        let activeProj = api.determineActiveProject() ?? ProjectSessionStore.shared.activeProject.map { XcodeProject(url: $0.directoryURL.appendingPathComponent("\($0.name).xcodeproj"), name: $0.name, schemes: []) }
        let projectName = api.determineProductName()
        let projectPath = activeProj?.url.path ?? ProjectSessionStore.shared.activeProject?.directoryURL.appendingPathComponent("\(projectName).xcodeproj").path ?? ""
        let scheme = api.determineActiveScheme()?.name ?? projectName
        let appBundleURL = api.determineAppBundleURL() ?? URL(fileURLWithPath: "\(projectPath)/build/DerivedData/Build/Products/Debug/\(projectName).app")
        let bundleID = api.determineBundleIdentifier()

        Task {
            await deploymentManager.startDeployment(
                device: selected,
                projectName: projectName,
                projectPath: projectPath,
                scheme: scheme,
                appBundleURL: appBundleURL,
                bundleIdentifier: bundleID
            )
        }
    }

    private func stopDeploymentRun() {
        guard let selected = deviceManager.selectedDevice else { return }
        let bundleID = XcodeBuildAPI.shared.determineBundleIdentifier()
        Task {
            _ = try? await RuntimeService().stop(deviceUDID: selected.udid, bundleIdentifier: bundleID)
            runtimeManager.stopMonitoring(deviceUDID: selected.udid)
        }
    }

    private func validateOrGenerateXcodeProject() {
        let api = XcodeBuildAPI.shared
        api.showProjectGenerationUI = true
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
