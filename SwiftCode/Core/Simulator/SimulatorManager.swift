import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "SimulatorManager")

/// The primary MainActor coordinator that serves as the single source of truth for simulator status and management.
@Observable
@MainActor
public final class SimulatorManager {
    public static let shared = SimulatorManager()

    public var devices: [SimulatorDevice] = []
    public var runtimes: [SimulatorRuntime] = []
    public var selectedDeviceID: String?
    public var isScanning = false
    public var consoleLogs: [SimulatorLogEntry] = []

    // Loaded simulation/deployment apps
    public var installedApps: [String: [SimulatorApplication]] = [:]

    private init() {
        Task {
            await refresh()
        }
    }

    public var selectedDevice: SimulatorDevice? {
        devices.first { $0.udid == selectedDeviceID }
    }

    /// Refresh devices and runtimes from systems and DiscoveryService
    public func refresh() async {
        isScanning = true
        await log("Scanning for simulators and platform runtimes...")

        let foundRuntimes = await SimulatorDiscoveryService.shared.discoverRuntimes()
        let foundDevices = await SimulatorDiscoveryService.shared.discoverDevices()

        self.runtimes = foundRuntimes
        self.devices = foundDevices

        if selectedDeviceID == nil, let firstBooted = foundDevices.first(where: { $0.state == .booted }) {
            selectedDeviceID = firstBooted.udid
        } else if selectedDeviceID == nil, let firstDevice = foundDevices.first {
            selectedDeviceID = firstDevice.udid
        }

        // Initialize sample mock/simulated applications for the devices to make the experience complete
        for device in foundDevices {
            if installedApps[device.udid] == nil {
                installedApps[device.udid] = [
                    SimulatorApplication(bundleIdentifier: "com.apple.mobilesafari", name: "Safari", version: "18.0", build: "1", bundlePath: "/Applications/Safari.app"),
                    SimulatorApplication(bundleIdentifier: "com.apple.Preferences", name: "Settings", version: "1.0", build: "1", bundlePath: "/Applications/Preferences.app")
                ]
            }
        }

        await log("Successfully loaded \(foundDevices.count) device(s) and \(foundRuntimes.count) runtime(s).")
        isScanning = false
    }

    /// Boots a given simulator device.
    public func bootDevice(udid: String) async {
        guard let idx = devices.firstIndex(where: { $0.udid == udid }) else { return }
        await log("Booting simulator device: \(devices[idx].name) (\(udid))...")

        do {
            _ = try await SimctlService.shared.execute(.boot(udid: udid))
            devices[idx] = SimulatorDevice(
                udid: devices[idx].udid,
                name: devices[idx].name,
                deviceTypeIdentifier: devices[idx].deviceTypeIdentifier,
                state: .booted,
                isAvailable: devices[idx].isAvailable,
                availabilityError: devices[idx].availabilityError,
                runtimeIdentifier: devices[idx].runtimeIdentifier
            )
            await log("Simulator booted successfully.", level: "SUCCESS")
        } catch SimulatorError.missingXcode {
            // Simulated fallback boot
            await log("Xcode CLI not detected. Performing virtual boot simulation...")
            try? await Task.sleep(nanoseconds: 800_000_000)
            devices[idx] = SimulatorDevice(
                udid: devices[idx].udid,
                name: devices[idx].name,
                deviceTypeIdentifier: devices[idx].deviceTypeIdentifier,
                state: .booted,
                isAvailable: devices[idx].isAvailable,
                availabilityError: devices[idx].availabilityError,
                runtimeIdentifier: devices[idx].runtimeIdentifier
            )
            await log("Virtual device booted successfully.", level: "SUCCESS")
        } catch {
            await log("Failed to boot device: \(error.localizedDescription)", level: "ERROR")
        }
    }

    /// Shuts down a given simulator device.
    public func shutdownDevice(udid: String) async {
        guard let idx = devices.firstIndex(where: { $0.udid == udid }) else { return }
        await log("Shutting down simulator device: \(devices[idx].name) (\(udid))...")

        do {
            _ = try await SimctlService.shared.execute(.shutdown(udid: udid))
            devices[idx] = SimulatorDevice(
                udid: devices[idx].udid,
                name: devices[idx].name,
                deviceTypeIdentifier: devices[idx].deviceTypeIdentifier,
                state: .shutdown,
                isAvailable: devices[idx].isAvailable,
                availabilityError: devices[idx].availabilityError,
                runtimeIdentifier: devices[idx].runtimeIdentifier
            )
            await log("Simulator shut down successfully.", level: "SUCCESS")
        } catch SimulatorError.missingXcode {
            // Simulated fallback shutdown
            await log("Xcode CLI not detected. Performing virtual shutdown simulation...")
            try? await Task.sleep(nanoseconds: 500_000_000)
            devices[idx] = SimulatorDevice(
                udid: devices[idx].udid,
                name: devices[idx].name,
                deviceTypeIdentifier: devices[idx].deviceTypeIdentifier,
                state: .shutdown,
                isAvailable: devices[idx].isAvailable,
                availabilityError: devices[idx].availabilityError,
                runtimeIdentifier: devices[idx].runtimeIdentifier
            )
            await log("Virtual device shut down successfully.", level: "SUCCESS")
        } catch {
            await log("Failed to shut down device: \(error.localizedDescription)", level: "ERROR")
        }
    }

    /// Erases all data and settings from a given simulator device.
    public func eraseDevice(udid: String) async {
        guard let idx = devices.firstIndex(where: { $0.udid == udid }) else { return }
        await log("Erasing simulator device: \(devices[idx].name) (\(udid))...")

        do {
            _ = try await SimctlService.shared.execute(.erase(udid: udid))
            await log("Simulator device erased successfully.", level: "SUCCESS")
        } catch SimulatorError.missingXcode {
            await log("Xcode CLI not detected. Performing virtual erase operation...")
            try? await Task.sleep(nanoseconds: 600_000_000)
            installedApps[udid] = []
            await log("Virtual device data and applications cleared.", level: "SUCCESS")
        } catch {
            await log("Failed to erase device: \(error.localizedDescription)", level: "ERROR")
        }
    }

    /// Deletes a given simulator device permanently.
    public func deleteDevice(udid: String) async {
        await log("Deleting simulator device with UDID: \(udid)...")

        do {
            _ = try await SimctlService.shared.execute(.delete(udid: udid))
            devices.removeAll { $0.udid == udid }
            installedApps.removeValue(forKey: udid)
            if selectedDeviceID == udid {
                selectedDeviceID = devices.first?.udid
            }
            await log("Simulator device deleted permanently.", level: "SUCCESS")
        } catch SimulatorError.missingXcode {
            await log("Xcode CLI not detected. Performing virtual delete operation...")
            try? await Task.sleep(nanoseconds: 400_000_000)
            devices.removeAll { $0.udid == udid }
            installedApps.removeValue(forKey: udid)
            if selectedDeviceID == udid {
                selectedDeviceID = devices.first?.udid
            }
            await log("Virtual device removed from local catalog.", level: "SUCCESS")
        } catch {
            await log("Failed to delete device: \(error.localizedDescription)", level: "ERROR")
        }
    }

    /// Creates a brand-new simulator device.
    public func createDevice(name: String, deviceType: String, runtime: String) async {
        await log("Creating simulator device '\(name)' with type '\(deviceType)' and runtime '\(runtime)'...")

        do {
            _ = try await SimctlService.shared.execute(.createDevice(name: name, deviceType: deviceType, runtime: runtime))
            await refresh()
            await log("Simulator device created successfully.", level: "SUCCESS")
        } catch SimulatorError.missingXcode {
            await log("Xcode CLI not detected. Simulating local device configuration...")
            try? await Task.sleep(nanoseconds: 500_000_000)
            let newUDID = UUID().uuidString
            let newDev = SimulatorDevice(
                udid: newUDID,
                name: name,
                deviceTypeIdentifier: deviceType,
                state: .shutdown,
                isAvailable: true,
                runtimeIdentifier: runtime
            )
            devices.append(newDev)
            installedApps[newUDID] = [
                SimulatorApplication(bundleIdentifier: "com.apple.mobilesafari", name: "Safari", version: "18.0", build: "1", bundlePath: "/Applications/Safari.app")
            ]
            selectedDeviceID = newUDID
            await log("Virtual device added to configuration.", level: "SUCCESS")
        } catch {
            await log("Failed to create simulator: \(error.localizedDescription)", level: "ERROR")
        }
    }

    /// Installs a native `.app` or `.ipa` file at the specified path on the selected simulator.
    public func deployApplication(at path: String, on deviceUDID: String) async {
        await log("Deploying application at path '\(path)' to simulator \(deviceUDID)...")

        do {
            let app = try await SimulatorInstallationService.shared.installApp(at: path, on: deviceUDID)
            if installedApps[deviceUDID] == nil {
                installedApps[deviceUDID] = []
            }
            installedApps[deviceUDID]?.append(app)
            await log("Installed app \(app.name) (\(app.bundleIdentifier)) successfully.", level: "SUCCESS")
        } catch {
            await log("Failed to deploy application: \(error.localizedDescription)", level: "ERROR")
        }
    }

    /// Launches an installed application.
    public func launchApplication(bundleID: String, on deviceUDID: String) async {
        await log("Launching application \(bundleID) on simulator \(deviceUDID)...")

        do {
            _ = try await SimctlService.shared.execute(.launch(udid: deviceUDID, bundleID: bundleID))
            await log("Launched application \(bundleID) successfully.", level: "SUCCESS")
        } catch SimulatorError.missingXcode {
            await log("Xcode CLI not detected. Simulating launching of target app bundle...")
            try? await Task.sleep(nanoseconds: 400_000_000)
            await log("App \(bundleID) launched (virtual session).", level: "SUCCESS")
        } catch {
            await log("Failed to launch application: \(error.localizedDescription)", level: "ERROR")
        }
    }

    /// Terminates a running application.
    public func terminateApplication(bundleID: String, on deviceUDID: String) async {
        await log("Terminating application \(bundleID) on simulator \(deviceUDID)...")

        do {
            _ = try await SimctlService.shared.execute(.terminate(udid: deviceUDID, bundleID: bundleID))
            await log("Terminated application \(bundleID) successfully.", level: "SUCCESS")
        } catch SimulatorError.missingXcode {
            await log("Xcode CLI not detected. Simulating application termination...")
            try? await Task.sleep(nanoseconds: 200_000_000)
            await log("App \(bundleID) terminated (virtual session).", level: "SUCCESS")
        } catch {
            await log("Failed to terminate application: \(error.localizedDescription)", level: "ERROR")
        }
    }

    /// Clears logs.
    public func clearLogs() async {
        await SimulatorLoggingService.shared.clear()
        consoleLogs = []
    }

    // MARK: - Internal Helper

    private func log(_ message: String, level: String = "INFO") async {
        await SimulatorLoggingService.shared.log(message, level: level)
        let entries = await SimulatorLoggingService.shared.getLogs()
        self.consoleLogs = entries
    }
}
