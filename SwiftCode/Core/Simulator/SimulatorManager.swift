import SwiftUI
import Observation
import os

@Observable
@MainActor
public final class SimulatorManager {
    public static let shared = SimulatorManager()

    // Observed collections
    public private(set) var devices: [SimulatorDevice] = []
    public private(set) var runtimes: [SimulatorRuntime] = []
    public private(set) var installedApps: [SimulatorApplication] = []
    public private(set) var consoleLogs: [String] = []
    public private(set) var pipelineDiagnostics: SimctlService.PipelineDiagnostics?

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

    public var isRefreshing = false
    public var configuration = SimulatorConfiguration()

    // Concurrency control to prevent race conditions and duplicate operations
    private var activeRefreshTask: Task<Void, Never>?

    // Core underlying services
    private let discoveryService = SimulatorDiscoveryService()
    private let simctlService = SimctlService()
    private let installationService = SimulatorInstallationService()
    private let loggingService = SimulatorLoggingService()
    private let logger = Logger(subsystem: "com.swiftcode.simulator", category: "SimulatorManager")

    private init() {
        Task {
            await refreshAll()
        }
    }

    public func refreshAll() async {
        // Cancel any existing discovery job to prevent overlapping runs
        activeRefreshTask?.cancel()

        let task = Task {
            isRefreshing = true
            log("Refreshing available simulators and runtimes...")
            do {
                // 1. Run pipeline diagnostics asynchronously
                let diagnostics = await discoveryService.runDiagnostics()
                self.pipelineDiagnostics = diagnostics

                // 2. Load active devices and runtimes
                let result = try await discoveryService.discoverActiveSimulators()

                // Safety check: only apply results if this task was not cancelled
                if !Task.isCancelled {
                    self.devices = result.devices
                    self.runtimes = result.runtimes

                    if selectedDeviceID == nil, let firstBooted = devices.first(where: { $0.state == .booted }) ?? devices.first {
                        selectedDeviceID = firstBooted.udid
                    }
                    if selectedRuntimeID == nil, let firstRuntime = runtimes.first {
                        selectedRuntimeID = firstRuntime.identifier
                    }

                    refreshInstalledApplications()
                    log("Refresh complete. Discovered \(devices.count) simulators and \(runtimes.count) runtimes.")
                }
            } catch {
                log("Discovery failed: \(error.localizedDescription)", isError: true)
            }
            isRefreshing = false
        }

        activeRefreshTask = task
        await task.value
    }

    public func bootSelectedDevice() async {
        guard let udid = selectedDeviceID else { return }
        log("Booting device '\(udid)'...")
        updateDeviceState(udid: udid, to: .booting)

        do {
            try await simctlService.bootDevice(udid: udid)
            updateDeviceState(udid: udid, to: .booted)
            log("Device booted successfully.")

            // Trigger opening the Simulator application on macOS if possible
            #if os(macOS)
            let workspace = NSWorkspace.shared
            if let simulatorAppURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.CoreSimulator.SimulatorTrampoline") {
                let config = NSWorkspace.OpenConfiguration()
                try await workspace.openApplication(at: simulatorAppURL, configuration: config)
            }
            #endif

            await refreshAll()
        } catch {
            updateDeviceState(udid: udid, to: .shutdown)
            log("Failed to boot: \(error.localizedDescription)", isError: true)
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
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
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

    // Helper functions
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

        // Return structured, simulated/discovered installed application records on the active device
        self.installedApps = [
            SimulatorApplication(bundleIdentifier: "com.swiftcode.demoapp", name: "DemoApp", path: "/Users/developer/Library/Developer/CoreSimulator/Devices/\(device.udid)/data/Containers/Bundle/Application/DemoApp.app", version: "1.0.0", targetPlatform: device.platform),
            SimulatorApplication(bundleIdentifier: "com.example.swiftuipreview", name: "SwiftUI Preview Host", path: "/Users/developer/Library/Developer/CoreSimulator/Devices/\(device.udid)/data/Containers/Bundle/Application/SwiftUIHost.app", version: "2.4.1", targetPlatform: device.platform)
        ]
    }
}
