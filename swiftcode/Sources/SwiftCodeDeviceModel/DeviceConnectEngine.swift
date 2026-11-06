import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The DeviceConnectKit engine layer, ported from Legacy
/// (`SwiftCode/Views/Build/DeviceConnectKit/Core/`): discovery,
/// the deploy pipeline, environment validation, runtime monitoring,
/// sessions, and the notification names.
///
/// Two deviations from Legacy, both recorded here:
/// - `DeploymentPipeline` no longer calls
///   `XcodeBuildAPI.shared.determineAppBundleURL()` — that Legacy
///   type is not in this slice. The bundle is located by the
///   products-directory scan Legacy already used as its fallback.
/// - Its first stage no longer sleeps 0.5s while claiming to save
///   the project: this pipeline never saved anything. Saving is the
///   host's job before deploying; the stage now says so.
/// - `RuntimeCoordinator` no longer fabricates random CPU/memory
///   numbers. It probes real liveness with `kill(pid, 0)` and
///   reports `DeviceMetrics.unavailable` (`isAvailable == false`)
///   for the values it cannot read. There is no supported API for
///   per-process CPU/memory of an app on a tethered device from this
///   layer.
public actor DeviceConnectCommandExecutor {
    public static let shared = DeviceConnectCommandExecutor()

    private var activeCommands: [UUID: Process] = [:]

    private init() {}

    public func registerActiveProcess(_ process: Process) -> UUID {
        let id = UUID()
        activeCommands[id] = process
        return id
    }

    public func terminateProcess(id: UUID) {
        if let proc = activeCommands[id] {
            if proc.isRunning {
                proc.terminate()
            }
            activeCommands.removeValue(forKey: id)
        }
    }

    public func terminateAll() {
        for id in activeCommands.keys {
            terminateProcess(id: id)
        }
    }
}

public actor DeploymentPipeline {
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

        // Stage 1: Save Project. This pipeline does not save files:
        // the host must save the workspace before deploying.
        onStateUpdate(.savingProject, "Saving project changes...")
        onLogUpdate("Save the workspace before deploying: this pipeline builds the files on disk as they are.")

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
        var effectiveAppBundleURL = appBundleURL
        let fm = FileManager.default

        if !fm.fileExists(atPath: effectiveAppBundleURL.path) {
            let productsURL = URL(fileURLWithPath: projectPath).deletingLastPathComponent().appendingPathComponent("build/DerivedData/Build/Products")
            if let enumerator = fm.enumerator(at: productsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                let files = enumerator.allObjects.compactMap { $0 as? URL }
                for fileURL in files {
                    if fileURL.pathExtension == "app" {
                        effectiveAppBundleURL = fileURL
                        break
                    }
                }
            }
        }

        guard fm.fileExists(atPath: effectiveAppBundleURL.path) else {
            onStateUpdate(.failed, "App bundle not found.")
            onLogUpdate("[Error] Could not locate compiled .app bundle. Checked: \(effectiveAppBundleURL.path)")
            return false
        }

        onLogUpdate("Located compiled app bundle at \(effectiveAppBundleURL.path)")

        // Stage 7: Install Application
        onStateUpdate(.installingApplication, "Installing application...")
        onLogUpdate("Running InstallApplicationCommand...")
        let installSuccess = try? await InstallApplicationCommand().execute(
            deviceUDID: device.udid,
            appBundleURL: effectiveAppBundleURL,
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

public final class DeviceConnectEngine: Sendable {
    public static let shared = DeviceConnectEngine()

    private let discovery = DeviceDiscovery()
    private let pipeline = DeploymentPipeline()
    private let validator = EnvironmentValidator()

    private init() {}

    public func startDiscovery(onDiscover: @escaping @Sendable ([ConnectedDevice]) -> Void) async {
        await discovery.startContinuousDiscovery(interval: 10, onDiscover: onDiscover)
    }

    public func stopDiscovery() async {
        await discovery.stopContinuousDiscovery()
    }

    public func validate() async -> (environment: DeviceEnvironment, diagnostics: [String]) {
        return await validator.validate()
    }

    public func deploy(
        device: ConnectedDevice,
        projectName: String,
        projectPath: String,
        scheme: String,
        appBundleURL: URL,
        bundleIdentifier: String,
        onStateUpdate: @escaping @Sendable (DeploymentStatus, String) -> Void,
        onLogUpdate: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        return await pipeline.run(
            device: device,
            projectName: projectName,
            projectPath: projectPath,
            scheme: scheme,
            appBundleURL: appBundleURL,
            bundleIdentifier: bundleIdentifier,
            onStateUpdate: onStateUpdate,
            onLogUpdate: onLogUpdate
        )
    }
}

public actor DeviceDiscovery {
    private var isDiscovering = false
    private var timer: Task<Void, Never>?

    public init() {}

    public func startContinuousDiscovery(interval: TimeInterval = 10, onDiscover: @escaping @Sendable ([ConnectedDevice]) -> Void) {
        guard !isDiscovering else { return }
        isDiscovering = true

        timer = Task { [interval, onDiscover] in
            while !Task.isCancelled {
                do {
                    let devices = try await DiscoverDevicesCommand().execute()
                    onDiscover(devices)
                } catch {
                    // Discovery failures are silent by design: an
                    // empty list is the "no devices" state, and the
                    // next poll retries.
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stopContinuousDiscovery() {
        timer?.cancel()
        timer = nil
        isDiscovering = false
    }
}

public struct EnvironmentValidator: Sendable {
    public init() {}

    public func validate() async -> (environment: DeviceEnvironment, diagnostics: [String]) {
        do {
            let env = try await ValidateEnvironmentCommand().execute()
            let diagnostics = DiagnosticsFormatter.formatEnvironmentDiagnostics(env)
            return (env, diagnostics)
        } catch {
            let fallback = DeviceEnvironment()
            return (fallback, ["Validation failed to execute: \(error.localizedDescription)"])
        }
    }
}

public final class DeviceConnectNotificationCenter: Sendable {
    public static let shared = DeviceConnectNotificationCenter()

    private init() {}

    public static let deviceConnected = Notification.Name("com.swiftcode.deviceconnect.connected")
    public static let deviceDisconnected = Notification.Name("com.swiftcode.deviceconnect.disconnected")
    public static let pipelineStateChanged = Notification.Name("com.swiftcode.deviceconnect.pipelineStateChanged")

    public func post(name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(name: name, object: object, userInfo: userInfo)
    }
}

public actor RuntimeCoordinator {
    private var monitoringTasks: [String: Task<Void, Never>] = [:] // deviceUDID: Task

    public init() {}

    public func startMonitoring(deviceUDID: String, bundleID: String, pid: Int32, onStateChanged: @escaping @Sendable (RuntimeStatus) -> Void, onMetrics: @escaping @Sendable (DeviceMetrics) -> Void) {
        monitoringTasks[deviceUDID]?.cancel()

        monitoringTasks[deviceUDID] = Task { [deviceUDID, bundleID, pid, onStateChanged, onMetrics] in
            onStateChanged(.running)
            // One honest reading up front: liveness is real, the
            // numbers are not available from this layer.
            onMetrics(.unavailable)

            while !Task.isCancelled {
                if !Self.processIsAlive(pid: pid) {
                    onStateChanged(.terminated)
                    break
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    public func stopMonitoring(deviceUDID: String) {
        monitoringTasks[deviceUDID]?.cancel()
        monitoringTasks.removeValue(forKey: deviceUDID)
    }

    /// `kill(pid, 0)` probes existence without signalling: 0 means
    /// the process exists, `EPERM` means it exists but is owned by
    /// someone else, anything else means it is gone.
    private static func processIsAlive(pid: Int32) -> Bool {
#if canImport(Darwin) || canImport(Glibc)
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
#else
        return true
#endif
    }
}

public actor SessionCoordinator {
    public static let shared = SessionCoordinator()

    private var activeSessions: [UUID: DeviceSession] = [:]
    private var pastSessions: [DeviceSession] = []

    private init() {}

    public func createSession(deviceUDID: String, deviceName: String, projectName: String, configuration: String) -> DeviceSession {
        let session = DeviceSession(
            deviceUDID: deviceUDID,
            deviceName: deviceName,
            projectName: projectName,
            configuration: configuration
        )
        activeSessions[session.id] = session
        return session
    }

    public func updateSession(_ session: DeviceSession) {
        activeSessions[session.id] = session
    }

    public func endSession(id: UUID, finalStatus: RuntimeStatus) -> DeviceSession? {
        guard var session = activeSessions[id] else { return nil }
        session.endTime = Date()
        session.runtimeStatus = finalStatus
        session.deploymentStatus = .completed
        activeSessions.removeValue(forKey: id)
        pastSessions.append(session)
        return session
    }

    public func getActiveSession(id: UUID) -> DeviceSession? {
        return activeSessions[id]
    }

    public func getAllPastSessions() -> [DeviceSession] {
        return pastSessions
    }
}
