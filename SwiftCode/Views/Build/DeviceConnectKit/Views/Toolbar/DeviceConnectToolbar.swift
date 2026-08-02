import SwiftUI

public struct DeviceConnectToolbar: View {
    @State private var deviceManager = DeviceManager.shared
    @State private var deploymentManager = DeploymentManager.shared
    @State private var environmentManager = EnvironmentManager.shared
    @State private var runtimeManager = RuntimeManager.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // Selected Device Pill Indicator
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .foregroundStyle(.blue)
                Text(deviceManager.selectedDevice?.name ?? "No Device Target")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: {
                Task {
                    await deviceManager.refreshDevices()
                }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(deviceManager.isDiscovering)

            Button(action: {
                Task {
                    await environmentManager.validateEnvironment()
                }
            }) {
                Label("Validate Env", systemImage: "checkmark.shield")
            }
            .disabled(environmentManager.isValidating)

            Divider()
                .frame(height: 20)

            // Build / Run / Stop controls
            Button(action: {
                triggerDeploymentRun()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    Text("Run")
                }
                .foregroundStyle(.green)
            }
            .disabled(deviceManager.selectedDevice == nil || deploymentManager.isDeploying)

            Button(action: {
                stopDeploymentRun()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .foregroundStyle(.red)
            }
            .disabled(!deploymentManager.isDeploying && runtimeManager.runtimeStatus != .running)

            Spacer()

            Button(action: {
                Task {
                    await environmentManager.clearDerivedData()
                }
            }) {
                Label("Clear DerivedData", systemImage: "trash.slash")
            }
            .disabled(environmentManager.isDerivedDataClearing)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
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
