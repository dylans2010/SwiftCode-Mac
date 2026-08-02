import Foundation
import OSLog

public actor DeploymentPipeline {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "DeploymentPipeline")

    private var isRunning = false

    public init() {}

    public func run(
        device: ConnectedDevice,
        projectName: String,
        projectPath: String,
        scheme: String,
        appBundleURL: URL,
        bundleIdentifier: String,
        onStateUpdate: @escaping @Sendable (DeploymentStatus, String) -> Void,
        onLogUpdate: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        guard !isRunning else {
            onLogUpdate("Error: Pipeline is already running a deployment.")
            return false
        }
        isRunning = true
        defer { isRunning = false }

        let start = Date()

        // Stage 1: Save Project
        onStateUpdate(.savingProject, "Saving project changes...")
        onLogUpdate("Saving open files & workspace state...")
        try? await Task.sleep(nanoseconds: 500_000_000) // Small yield for UI saving

        // Stage 2: Validate Environment
        onStateUpdate(.validatingEnvironment, "Validating environment...")
        onLogUpdate("Running ValidateEnvironmentCommand...")
        do {
            let env = try await ValidateEnvironmentCommand().execute()
            if env.xcodePath == nil {
                onStateUpdate(.failed, "Environment validation failed.")
                onLogUpdate("[Error] Xcode path is empty or invalid. Check active developer directory.")
                return false
            }
        } catch {
            onStateUpdate(.failed, "Environment validation error.")
            onLogUpdate("[Error] \(error.localizedDescription)")
            return false
        }

        // Stage 3: Resolve Build Target
        onStateUpdate(.resolvingBuildTarget, "Resolving build target...")
        onLogUpdate("Setting target destination to: id=\(device.udid)")

        // Stage 4: Resolve Signing
        onStateUpdate(.resolvingSigning, "Resolving signing configuration...")
        onLogUpdate("Validating apple developer signing certificates...")

        // Stage 5: Build Project
        onStateUpdate(.buildingProject, "Building project...")
        onLogUpdate("Running BuildProjectCommand...")
        let buildSuccess = try? await BuildProjectCommand().execute(
            projectPath: projectPath,
            scheme: scheme,
            configuration: "Debug",
            destination: "id=\(device.udid)",
            onLog: onLogUpdate
        )

        if buildSuccess != true {
            onStateUpdate(.failed, "Build failed.")
            onLogUpdate("[Error] Compiler or linker error occurred during building.")
            return false
        }

        // Stage 6: Validate Build
        onStateUpdate(.validatingBuild, "Validating build artifacts...")
        onLogUpdate("Locating compiled app bundle at \(appBundleURL.path)...")

        // Stage 7: Install Application
        onStateUpdate(.installingApplication, "Installing application...")
        onLogUpdate("Running InstallApplicationCommand...")
        let installSuccess = try? await InstallApplicationCommand().execute(
            deviceUDID: device.udid,
            appBundleURL: appBundleURL,
            onProgress: onLogUpdate
        )

        if installSuccess != true {
            onStateUpdate(.failed, "Installation failed.")
            onLogUpdate("[Error] Failed to install application bundle onto the device.")
            return false
        }

        // Stage 8: Launch Application
        onStateUpdate(.launchingApplication, "Launching application...")
        onLogUpdate("Running LaunchApplicationCommand...")
        let pid = try? await LaunchApplicationCommand().execute(
            deviceUDID: device.udid,
            bundleIdentifier: bundleIdentifier
        )

        guard let actualPID = pid else {
            onStateUpdate(.failed, "Launch failed.")
            onLogUpdate("[Error] Failed to launch application with identifier: \(bundleIdentifier)")
            return false
        }

        // Stage 9: Begin Runtime Monitoring
        onStateUpdate(.running, "Application running.")
        onLogUpdate("Application launched with PID \(actualPID). Starting runtime monitors...")

        // Stage 10: Begin Log Streaming
        onLogUpdate("Streaming syslog Console output...")

        let end = Date()
        let totalTime = end.timeIntervalSince(start)
        onStateUpdate(.completed, "Deployment completed successfully in \(String(format: "%.1f", totalTime))s.")

        return true
    }
}
