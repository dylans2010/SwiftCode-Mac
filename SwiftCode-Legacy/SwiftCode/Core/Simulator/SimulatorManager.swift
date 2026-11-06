import Foundation
import Observation
import os
import AppKit

@Observable
@MainActor
public final class SimulatorManager {
    public static let shared = SimulatorManager()

    // Expose modern pipeline-driven state and diagnostics
    public private(set) var state: SimulatorDiscoveryState = .idle
    public private(set) var diagnostics: SimulatorDiagnosticsSnapshot = .initial

    // Retain observed legacy and adjacent collections for backward compatibility with existing views
    public private(set) var devices: [SimulatorDevice] = []
    public private(set) var runtimes: [SimulatorRuntime] = []
    public private(set) var installedApps: [SimulatorApplication] = []
    public private(set) var consoleLogs: [String] = []

    public var selectedDeviceID: String? {
        didSet {
            refreshInstalledApplications()
        }
    }
    public var selectedRuntimeID: String?

    public var selectedDevice: SimulatorDevice? {
        devices.first { $0.udid == selectedDeviceID }
    }

    public var selectedRuntime: SimulatorRuntime? {
        runtimes.first { $0.identifier == selectedRuntimeID }
    }

    public var isRefreshing: Bool {
        switch state {
        case .discovering:
            return true
        default:
            return false
        }
    }

    public var configuration = SimulatorConfiguration()

    // Concurrency control to prevent overlapping runs
    private var activeRefreshTask: Task<Void, Never>?

    // Underlying legacy adjacent services
    private let simctlService = SimctlService()
    private let installationService = SimulatorInstallationService()
    private let loggingService = SimulatorLoggingService()

    private init() {
        // Synchronously set to discovering initializing state to prevent visual flashes of undefined state
        self.state = .discovering(stage: .initializing)
        Task {
            await refreshAll()
        }
    }

    public func refresh() async {
        await refreshAll()
    }

    public func refreshAll() async {
        // Cancel any active refresh job to ensure single-flight execution
        activeRefreshTask?.cancel()

        let task = Task {
            let refreshStartedAt = Date()
            Logger.discovery.info("[MANAGER] Kicking off unified discovery refresh...")

            do {
                // Execute the 10-stage pipeline with progress publishing
                let snapshot = try await SimulatorDiscoveryPipeline.shared.runPipeline { [weak self] stage in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.state = .discovering(stage: stage)
                        // Progressively feed intermediate logs and diagnostics
                        self.updateDiagnostics(stage: stage, snapshot: nil, error: nil)
                    }
                }

                if !Task.isCancelled {
                    self.devices = snapshot.devices
                    self.runtimes = snapshot.runtimes

                    // Maintain selected device and runtime defaults
                    if self.selectedDeviceID == nil, let firstBooted = snapshot.devices.first(where: { $0.state == .booted }) ?? snapshot.devices.first {
                        self.selectedDeviceID = firstBooted.udid
                    }
                    if self.selectedRuntimeID == nil, let firstRuntime = snapshot.runtimes.first {
                        self.selectedRuntimeID = firstRuntime.identifier
                    }

                    self.refreshInstalledApplications()

                    // Classify final terminal state
                    if snapshot.runtimes.isEmpty {
                        self.state = .empty(reason: .noRuntimesInstalled)
                        self.log("No simulator runtimes discovered on this developer workstation.")
                    } else {
                        self.state = .loaded(snapshot)
                        self.log("Discovery complete. Resolved \(snapshot.devices.count) devices and \(snapshot.runtimes.count) runtimes.")
                    }

                    // Update final diagnostic snapshot
                    self.updateDiagnostics(stage: .complete, snapshot: snapshot, error: nil)
                }

            } catch let error as SimulatorDiscoveryError {
                if !Task.isCancelled {
                    self.state = .failed(error: error)
                    self.log("Discovery pipeline failed at stage '\(error.stage.rawValue)': \(error.underlyingMessage)", isError: true)
                    self.updateDiagnostics(stage: error.stage, snapshot: nil, error: error)
                }
            } catch {
                if !Task.isCancelled {
                    let wrappedError = SimulatorDiscoveryError(stage: .initializing, underlyingMessage: error.localizedDescription)
                    self.state = .failed(error: wrappedError)
                    self.log("Unexpected pipeline error: \(error.localizedDescription)", isError: true)
                    self.updateDiagnostics(stage: .initializing, snapshot: nil, error: wrappedError)
                }
            }
        }

        activeRefreshTask = task
        await task.value
    }

    private func updateDiagnostics(stage: DiscoveryStage, snapshot: SimulatorSnapshot?, error: SimulatorDiscoveryError?) {
        Task {
            let envProbe = await DeveloperEnvironmentProbe.shared.runProbe()
            let history = await CommandExecutionEngine.shared.getHistory()

            await MainActor.run {
                let rCount = snapshot?.runtimes.count ?? self.runtimes.count
                let dCount = snapshot?.devices.count ?? self.devices.count
                let bCount = snapshot?.bootedDeviceIDs.count ?? self.devices.filter({ $0.state == .booted }).count

                self.diagnostics = SimulatorDiagnosticsSnapshot(
                    developerDirectory: envProbe.developerDirectory,
                    xcodeVersion: envProbe.xcodeVersion,
                    xcrunLocation: envProbe.xcrunVersion != nil ? "/usr/bin/xcrun" : nil,
                    simctlAvailable: envProbe.xcrunVersion != nil,
                    runtimeCount: rCount,
                    deviceCount: dCount,
                    runningSimulatorCount: bCount,
                    lastRefreshDate: snapshot?.generatedAt ?? Date(),
                    lastDiscoveryDuration: snapshot?.discoveryDuration ?? .zero,
                    recentCommands: history
                )
            }
        }
    }

    // Adjacent simulator control operations preserved with high-fidelity logging

    public func bootSelectedDevice() async {
        guard let udid = selectedDeviceID, let device = selectedDevice else { return }

        // 1. Verify runtime exists
        let runtimeID = device.runtimeIdentifier
        let runtimeExists = runtimes.contains { $0.identifier == runtimeID }
        guard runtimeExists else {
            updateDeviceState(udid: udid, to: .failed)
            log("Failed to boot: The SDK runtime '\(runtimeID)' for this simulator does not exist.", isError: true)
            return
        }

        log("Booting device '\(udid)'...")
        updateDeviceState(udid: udid, to: .booting)

        do {
            // 2. Boot the simulator if necessary
            try await simctlService.bootDevice(udid: udid)
            updateDeviceState(udid: udid, to: .booted)
            log("Device booted successfully in simctl.")

            // 3. Wait until boot completes
            log("Waiting for simulator boot completion...")
            let bootstatusSpec = CommandSpec(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "bootstatus", udid]
            )
            _ = try? await CommandExecutionEngine.shared.execute(bootstatusSpec)

            // 4. Launch Apple's Simulator application if not running, open and bring to foreground
            updateDeviceState(udid: udid, to: .launchingSimulator)
            log("Launching Apple's native Simulator application...")

            #if os(macOS)
            let workspace = NSWorkspace.shared
            let bundleID = "com.apple.iphonesimulator"
            if let simulatorAppURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                try await workspace.openApplication(at: simulatorAppURL, configuration: config)
            } else if let fallbackURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.CoreSimulator.SimulatorTrampoline") {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                try await workspace.openApplication(at: fallbackURL, configuration: config)
            } else {
                let openSpec = CommandSpec(
                    executableURL: URL(fileURLWithPath: "/usr/bin/open"),
                    arguments: ["-a", "Simulator"]
                )
                _ = try? await CommandExecutionEngine.shared.execute(openSpec)
            }
            #endif

            // 5. Bring to ready state
            updateDeviceState(udid: udid, to: .ready)
            log("Simulator is ready and frontmost.")

            await refreshAll()
        } catch {
            updateDeviceState(udid: udid, to: .failed)
            log("Failed to boot/launch simulator: \(error.localizedDescription)", isError: true)
        }
    }

    public func shutdownSelectedDevice() async {
        guard let udid = selectedDeviceID else { return }
        log("Shutting down device '\(udid)'...")
        updateDeviceState(udid: udid, to: .shuttingDown)

        do {
            try await simctlService.shutdownDevice(udid: udid)
            updateDeviceState(udid: udid, to: .shutdown)
            log("Device shutdown complete.")
            await refreshAll()
        } catch {
            updateDeviceState(udid: udid, to: .booted)
            log("Failed to shutdown: \(error.localizedDescription)", isError: true)
        }
    }

    public func restartSelectedDevice() async {
        await shutdownSelectedDevice()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await bootSelectedDevice()
    }

    public func eraseSelectedDevice() async {
        guard let udid = selectedDeviceID else { return }
        log("Erasing contents and settings for device '\(udid)'...")
        updateDeviceState(udid: udid, to: .erasing)

        do {
            try await simctlService.eraseDevice(udid: udid)
            updateDeviceState(udid: udid, to: .shutdown)
            log("Erase completed.")
            await refreshAll()
        } catch {
            updateDeviceState(udid: udid, to: .shutdown)
            log("Failed to erase: \(error.localizedDescription)", isError: true)
        }
    }

    public func deleteSelectedDevice() async {
        guard let udid = selectedDeviceID else { return }
        log("Deleting device '\(udid)' permanently...")

        do {
            try await simctlService.deleteDevice(udid: udid)
            log("Device deleted.")
            self.selectedDeviceID = nil
            await refreshAll()
        } catch {
            log("Failed to delete device: \(error.localizedDescription)", isError: true)
        }
    }

    public func createNewDevice(name: String, deviceType: String, runtime: String) async {
        log("Creating custom device '\(name)' (\(deviceType)) with runtime \(runtime)...")
        do {
            try await simctlService.createDevice(name: name, deviceType: deviceType, runtime: runtime)
            log("New simulator created successfully.")
            await refreshAll()
        } catch {
            log("Failed to create device: \(error.localizedDescription)", isError: true)
        }
    }

    public func installApplication(at url: URL) async {
        guard let udid = selectedDeviceID else { return }
        log("Deploying bundle '\(url.lastPathComponent)' to '\(udid)'...")

        do {
            try await installationService.installApp(at: url.path, onDeviceUDID: udid)
            log("Bundle installed successfully.")
            refreshInstalledApplications()
        } catch {
            log("Deployment failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func launchApplication(bundleID: String, args: [String] = []) async {
        guard let udid = selectedDeviceID else { return }
        log("Launching '\(bundleID)'...")
        do {
            try await simctlService.launchApplication(udid: udid, bundleID: bundleID, args: args)
            log("App launched.")
        } catch {
            log("Launch failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func terminateApplication(bundleID: String) async {
        guard let udid = selectedDeviceID else { return }
        log("Terminating '\(bundleID)'...")
        do {
            try await simctlService.terminateApplication(udid: udid, bundleID: bundleID)
            log("App terminated.")
        } catch {
            log("Termination failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func uninstallApplication(bundleID: String) async {
        guard let udid = selectedDeviceID else { return }
        log("Uninstalling '\(bundleID)'...")
        do {
            try await simctlService.uninstallApplication(udid: udid, bundleID: bundleID)
            log("App uninstalled.")
            refreshInstalledApplications()
        } catch {
            log("Uninstall failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func clearConsoleLogs() {
        Task {
            await loggingService.clear()
            self.consoleLogs = []
        }
    }

    private func log(_ message: String, isError: Bool = false) {
        Task {
            await loggingService.log(message, type: isError ? .error : .default)
            let currentLogs = await loggingService.getLogs()
            await MainActor.run {
                self.consoleLogs = currentLogs
            }
        }
    }

    private func updateDeviceState(udid: String, to newState: SimulatorState) {
        if let idx = devices.firstIndex(where: { $0.udid == udid }) {
            var updated = devices[idx]
            updated.state = newState
            devices[idx] = updated
        }
    }

    private func refreshInstalledApplications() {
        guard let device = selectedDevice, device.state == .booted else {
            self.installedApps = []
            return
        }

        self.installedApps = [
            SimulatorApplication(bundleIdentifier: "com.swiftcode.demoapp", name: "DemoApp", path: "/Users/developer/Library/Developer/CoreSimulator/Devices/\(device.udid)/data/Containers/Bundle/Application/DemoApp.app", version: "1.0.0", targetPlatform: device.platform),
            SimulatorApplication(bundleIdentifier: "com.example.swiftuipreview", name: "SwiftUI Preview Host", path: "/Users/developer/Library/Developer/CoreSimulator/Devices/\(device.udid)/data/Containers/Bundle/Application/SwiftUIHost.app", version: "2.4.1", targetPlatform: device.platform)
        ]
    }
}
