import Foundation
import Observation

/// The DeviceConnectKit managers, ported from Legacy
/// (`SwiftCode/Views/Build/DeviceConnectKit/Managers/`): the
/// `@Observable` state holders the DeviceConnect UI binds to.
///
/// Renames from Legacy, all mechanical: the bare names
/// (`BuildManager`, `SessionManager`, `DeviceManager`, …) collide
/// with `SwiftCodeBuild` / `SwiftCodeSDK` types of the same name in modules
/// `SwiftCodeUI` also imports, so every manager here carries the
/// `DeviceConnect` prefix. Behaviour is Legacy's, except
/// `DeviceConnectRuntimeManager.stopMonitoring`, which now actually
/// stops the coordinator task Legacy leaked (Legacy created a fresh
/// `RuntimeCoordinator` per start and never cancelled it).
@Observable
@MainActor
public final class DeviceConnectBuildManager {
    public static let shared = DeviceConnectBuildManager()

    public private(set) var buildStatus: DeviceBuildStatus = .idle
    public private(set) var errors: [BuildParser.ParsedIssue] = []
    public private(set) var warnings: [BuildParser.ParsedIssue] = []
    public private(set) var buildDuration: TimeInterval = 0

    private init() {}

    public func startBuild() {
        buildStatus = .building
        errors.removeAll()
        warnings.removeAll()
        buildDuration = 0
    }

    public func finishBuild(success: Bool, rawLogs: String, duration: TimeInterval) {
        buildStatus = success ? .succeeded : .failed
        buildDuration = duration

        let issues = BuildParser.parseXcodebuildOutput(rawLogs)
        self.errors = issues.errors
        self.warnings = issues.warnings
    }
}

@Observable
@MainActor
public final class DeviceConnectConsoleManager {
    public static let shared = DeviceConnectConsoleManager()

    public private(set) var buildLogs: [DeviceLog] = []
    public private(set) var runtimeLogs: [DeviceLog] = []

    public var selectedConsoleTab: Int = 0 // 0: Build, 1: Runtime

    private init() {}

    public func appendLog(_ log: DeviceLog) {
        if log.type == .build {
            buildLogs.append(log)
        } else {
            runtimeLogs.append(log)
        }
    }

    public func clearLogs() {
        if selectedConsoleTab == 0 {
            buildLogs.removeAll()
        } else {
            runtimeLogs.removeAll()
        }
    }
}

@Observable
@MainActor
public final class DeviceConnectDeploymentManager {
    public static let shared = DeviceConnectDeploymentManager()

    public private(set) var deploymentStatus: DeploymentStatus = .idle
    public private(set) var currentStageDescription = "Idle"
    public private(set) var isDeploying = false
    public private(set) var logs: [DeviceLog] = []

    private init() {}

    public func startDeployment(
        device: ConnectedDevice,
        projectName: String,
        projectPath: String,
        scheme: String,
        appBundleURL: URL,
        bundleIdentifier: String
    ) async {
        guard !isDeploying else { return }
        isDeploying = true
        logs.removeAll()

        let session = DeviceConnectSessionManager.shared.createSession(
            device: device,
            projectName: projectName,
            configuration: "Debug"
        )

        let success = await DeviceConnectEngine.shared.deploy(
            device: device,
            projectName: projectName,
            projectPath: projectPath,
            scheme: scheme,
            appBundleURL: appBundleURL,
            bundleIdentifier: bundleIdentifier,
            onStateUpdate: { [weak self] status, desc in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.deploymentStatus = status
                    self.currentStageDescription = desc

                    var updatedSession = session
                    updatedSession.deploymentStatus = status
                    if status == .running {
                        updatedSession.runtimeStatus = .running
                    } else if status == .completed {
                        updatedSession.endTime = Date()
                    } else if status == .failed {
                        updatedSession.endTime = Date()
                        updatedSession.buildStatus = .failed
                    }
                    DeviceConnectSessionManager.shared.updateActiveSession(updatedSession)

                    if status == .completed || status == .failed || status == .cancelled {
                        self.isDeploying = false
                        let historyItem = DeploymentHistory(
                            projectName: projectName,
                            deviceName: device.name,
                            deviceUDID: device.udid,
                            duration: Date().timeIntervalSince(session.startTime),
                            buildResult: status == .failed ? .failed : .succeeded,
                            deployResult: status,
                            runResult: status == .completed ? .running : .idle
                        )
                        DeviceConnectHistoryManager.shared.addHistoryItem(historyItem)
                    }
                }
            },
            onLogUpdate: { [weak self] logLine in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let parsedLog = LogParser.parseLogLine(logLine, type: .build)
                    self.logs.append(parsedLog)
                    DeviceConnectConsoleManager.shared.appendLog(parsedLog)
                }
            }
        )

        if success {
            DeviceConnectNotificationService.shared.postNotification(
                title: "Deployment Successful",
                subtitle: device.name,
                body: "Successfully deployed and launched \(projectName)."
            )
        } else {
            DeviceConnectNotificationService.shared.postNotification(
                title: "Deployment Failed",
                subtitle: device.name,
                body: "Failed to deploy \(projectName). Please check build logs."
            )
        }
    }
}

@Observable
@MainActor
public final class DeviceConnectRuntimeManager {
    public static let shared = DeviceConnectRuntimeManager()

    public private(set) var runtimeStatus: RuntimeStatus = .idle
    public private(set) var metrics: DeviceMetrics = DeviceMetrics()
    public private(set) var activePID: Int32? = nil

    private var coordinator: RuntimeCoordinator?

    private init() {}

    public func updateRuntimeStatus(_ status: RuntimeStatus) {
        self.runtimeStatus = status
    }

    public func updateMetrics(_ metrics: DeviceMetrics) {
        self.metrics = metrics
    }

    public func startMonitoring(deviceUDID: String, bundleID: String, pid: Int32) {
        self.activePID = pid
        self.runtimeStatus = .running

        let coordinator = RuntimeCoordinator()
        self.coordinator = coordinator
        Task {
            await coordinator.startMonitoring(
                deviceUDID: deviceUDID,
                bundleID: bundleID,
                pid: pid,
                onStateChanged: { [weak self] status in
                    Task { @MainActor [weak self] in
                        self?.runtimeStatus = status
                    }
                },
                onMetrics: { [weak self] nextMetrics in
                    Task { @MainActor [weak self] in
                        self?.metrics = nextMetrics
                    }
                }
            )
        }
    }

    public func stopMonitoring(deviceUDID: String) {
        self.activePID = nil
        self.runtimeStatus = .idle
        if let coordinator {
            self.coordinator = nil
            Task { await coordinator.stopMonitoring(deviceUDID: deviceUDID) }
        }
    }
}

@Observable
@MainActor
public final class DeviceConnectDeviceManager {
    public static let shared = DeviceConnectDeviceManager()

    public private(set) var devices: [ConnectedDevice] = []
    public var selectedDevice: ConnectedDevice?
    public var isDiscovering = false

    private let service = DeviceConnectDeviceService()

    private init() {}

    public func startDiscovery() async {
        guard !isDiscovering else { return }
        isDiscovering = true

        await DeviceConnectEngine.shared.startDiscovery { [weak self] discovered in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.devices = discovered
                // Auto-select first device if none is selected
                if self.selectedDevice == nil, let first = discovered.first {
                    self.selectedDevice = first
                }
            }
        }
    }

    public func stopDiscovery() async {
        await DeviceConnectEngine.shared.stopDiscovery()
        isDiscovering = false
    }

    public func refreshDevices() async {
        do {
            let discovered = try await service.discover()
            self.devices = discovered
            if self.selectedDevice == nil || !discovered.contains(where: { $0.udid == self.selectedDevice?.udid }) {
                self.selectedDevice = discovered.first
            }
        } catch {
            self.devices = []
        }
    }

    public func selectDevice(_ device: ConnectedDevice) {
        self.selectedDevice = device
        // Raise notification
        DeviceConnectNotificationCenter.shared.post(
            name: DeviceConnectNotificationCenter.deviceConnected,
            userInfo: ["device": device]
        )
    }
}

@Observable
@MainActor
public final class DeviceConnectEnvironmentManager {
    public static let shared = DeviceConnectEnvironmentManager()

    public private(set) var currentEnvironment: DeviceEnvironment = DeviceEnvironment()
    public private(set) var diagnostics: [String] = []
    public private(set) var isValidating = false
    public private(set) var isDerivedDataClearing = false
    public private(set) var derivedDataSize: Double = 0

    private init() {}

    public func validateEnvironment() async {
        isValidating = true
        let result = await DeviceConnectEngine.shared.validate()
        self.currentEnvironment = result.environment
        self.diagnostics = result.diagnostics

        // Update derived data size
        do {
            self.derivedDataSize = try await DerivedDataCommand().getDerivedDataSize()
        } catch {
            self.derivedDataSize = 0
        }

        isValidating = false
    }

    public func clearDerivedData() async {
        isDerivedDataClearing = true
        do {
            _ = try await DerivedDataCommand().clearDerivedData()
            self.derivedDataSize = 0
        } catch {}
        isDerivedDataClearing = false
    }
}

@Observable
@MainActor
public final class DeviceConnectHistoryManager {
    public static let shared = DeviceConnectHistoryManager()

    public private(set) var historyItems: [DeploymentHistory] = []

    private init() {}

    public func addHistoryItem(_ item: DeploymentHistory) {
        historyItems.insert(item, at: 0)
    }

    public func removeHistoryItem(_ item: DeploymentHistory) {
        historyItems.removeAll(where: { $0.id == item.id })
    }

    public func clearHistory() {
        historyItems.removeAll()
    }
}

@Observable
@MainActor
public final class DeviceConnectPreferencesManager {
    public static let shared = DeviceConnectPreferencesManager()

    // Configs persisted via UserDefaults. The keys keep Legacy's
    // `com.swiftcode.deviceconnect.*` names so an existing install
    // keeps its preferences.
    public var autoDiscover: Bool {
        didSet { UserDefaults.standard.set(autoDiscover, forKey: "com.swiftcode.deviceconnect.autoDiscover") }
    }
    public var autoValidate: Bool {
        didSet { UserDefaults.standard.set(autoValidate, forKey: "com.swiftcode.deviceconnect.autoValidate") }
    }
    public var autoSaveBeforeDeploy: Bool {
        didSet { UserDefaults.standard.set(autoSaveBeforeDeploy, forKey: "com.swiftcode.deviceconnect.autoSaveBeforeDeploy") }
    }
    public var autoLaunch: Bool {
        didSet { UserDefaults.standard.set(autoLaunch, forKey: "com.swiftcode.deviceconnect.autoLaunch") }
    }
    public var autoStreamLogs: Bool {
        didSet { UserDefaults.standard.set(autoStreamLogs, forKey: "com.swiftcode.deviceconnect.autoStreamLogs") }
    }
    public var showNotifications: Bool {
        didSet { UserDefaults.standard.set(showNotifications, forKey: "com.swiftcode.deviceconnect.showNotifications") }
    }
    public var keepHistory: Bool {
        didSet { UserDefaults.standard.set(keepHistory, forKey: "com.swiftcode.deviceconnect.keepHistory") }
    }
    public var maxSessionCount: Int {
        didSet { UserDefaults.standard.set(maxSessionCount, forKey: "com.swiftcode.deviceconnect.maxSessionCount") }
    }

    private init() {
        self.autoDiscover = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoDiscover") as? Bool ?? true
        self.autoValidate = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoValidate") as? Bool ?? true
        self.autoSaveBeforeDeploy = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoSaveBeforeDeploy") as? Bool ?? true
        self.autoLaunch = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoLaunch") as? Bool ?? true
        self.autoStreamLogs = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoStreamLogs") as? Bool ?? true
        self.showNotifications = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.showNotifications") as? Bool ?? true
        self.keepHistory = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.keepHistory") as? Bool ?? true
        self.maxSessionCount = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.maxSessionCount") as? Int ?? 50
    }
}

@Observable
@MainActor
public final class DeviceConnectSessionManager {
    public static let shared = DeviceConnectSessionManager()

    public private(set) var activeSession: DeviceSession?
    public private(set) var sessionsHistory: [DeviceSession] = []

    private init() {}

    public func createSession(device: ConnectedDevice, projectName: String, configuration: String) -> DeviceSession {
        let session = DeviceSession(
            deviceUDID: device.udid,
            deviceName: device.name,
            projectName: projectName,
            configuration: configuration
        )
        activeSession = session
        sessionsHistory.append(session)
        return session
    }

    public func updateActiveSession(_ session: DeviceSession) {
        self.activeSession = session
        if let idx = sessionsHistory.firstIndex(where: { $0.id == session.id }) {
            sessionsHistory[idx] = session
        } else {
            sessionsHistory.append(session)
        }
    }

    public func endActiveSession(finalStatus: RuntimeStatus) {
        guard var session = activeSession else { return }
        session.endTime = Date()
        session.runtimeStatus = finalStatus
        session.deploymentStatus = .completed
        updateActiveSession(session)
        activeSession = nil
    }

    public func clearHistory() {
        sessionsHistory.removeAll()
    }
}

@Observable
@MainActor
public final class DeviceConnectSigningManager {
    public static let shared = DeviceConnectSigningManager()

    public private(set) var signingStatus: SigningStatus = .idle
    public private(set) var availableIdentities: [String] = []

    private let service = DeviceConnectSigningService()

    private init() {}

    public func verifySigning() async {
        signingStatus = .verifying
        do {
            let identities = try await service.validateIdentities()
            self.availableIdentities = identities
            if !identities.isEmpty {
                self.signingStatus = .valid
            } else {
                self.signingStatus = .invalid
            }
        } catch {
            self.availableIdentities = []
            self.signingStatus = .invalid
        }
    }
}
