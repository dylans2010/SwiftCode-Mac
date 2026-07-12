import Foundation
import os

public actor SimctlService {
    private let executor = SimulatorCommandExecutor()
    private let logger = Logger(subsystem: "com.swiftcode.simulator", category: "SimctlService")

    public init() {}

    public func fetchDevicesAndRuntimes() async throws -> (devices: [SimulatorDevice], runtimes: [SimulatorRuntime]) {
        let command = SimulatorCommand.listDevices()
        let result = try await executor.execute(command)

        guard result.exitCode == 0 else {
            throw SimulatorError.simctlFailed(reason: "List command returned non-zero code. Output: \(result.errorOutput)")
        }

        guard let data = result.output.data(using: .utf8) else {
            throw SimulatorError.simctlFailed(reason: "Invalid list response encoding")
        }

        // Parsing the simctl JSON format
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // 1. Parse runtimes
            var parsedRuntimes: [SimulatorRuntime] = []
            if let runtimesList = json["runtimes"] as? [[String: Any]] {
                for r in runtimesList {
                    let identifier = r["identifier"] as? String ?? ""
                    let name = r["name"] as? String ?? ""
                    let version = r["version"] as? String ?? ""
                    let platform = r["platform"] as? String ?? (name.contains("iOS") ? "iOS" : name.contains("watchOS") ? "watchOS" : name.contains("tvOS") ? "tvOS" : "visionOS")
                    let isAvailable = r["isAvailable"] as? Bool ?? true

                    parsedRuntimes.append(SimulatorRuntime(
                        identifier: identifier,
                        name: name,
                        version: version,
                        platform: platform,
                        isAvailable: isAvailable
                    ))
                }
            }

            // 2. Parse devices
            var parsedDevices: [SimulatorDevice] = []
            if let devicesMap = json["devices"] as? [String: [[String: Any]]] {
                for (runtimeKey, devList) in devicesMap {
                    // Match runtime version and platform
                    let cleanRuntimeID = runtimeKey.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                    let parts = cleanRuntimeID.split(separator: "-")
                    let platform = parts.first.map(String.init) ?? "iOS"
                    let version = parts.dropFirst().joined(separator: ".")

                    for d in devList {
                        let udid = d["udid"] as? String ?? ""
                        let name = d["name"] as? String ?? ""
                        let stateStr = d["state"] as? String ?? "Shutdown"
                        let isAvailable = d["isAvailable"] as? Bool ?? true

                        let state: SimulatorState = {
                            switch stateStr.lowercased() {
                            case "booted": return .booted
                            case "booting": return .booting
                            case "shutting down": return .shuttingDown
                            case "shutdown": return .shutdown
                            default: return .unknown
                            }
                        }()

                        parsedDevices.append(SimulatorDevice(
                            udid: udid,
                            name: name,
                            runtimeIdentifier: runtimeKey,
                            platform: platform,
                            osVersion: version,
                            architecture: "arm64", // Default simulator architecture
                            state: state,
                            isAvailable: isAvailable
                        ))
                    }
                }
            }

            return (parsedDevices, parsedRuntimes)

        } catch {
            logger.error("[FAILED] parsing simctl JSON list: \(error.localizedDescription)")
            throw SimulatorError.simctlFailed(reason: "JSON decoding failed: \(error.localizedDescription)")
        }
    }

    public func bootDevice(udid: String) async throws {
        let command = SimulatorCommand.boot(udid: udid)
        let result = try await executor.execute(command)
        if result.exitCode != 0 {
            throw SimulatorError.simctlFailed(reason: result.errorOutput)
        }
    }

    public func shutdownDevice(udid: String) async throws {
        let command = SimulatorCommand.shutdown(udid: udid)
        let result = try await executor.execute(command)
        if result.exitCode != 0 {
            throw SimulatorError.simctlFailed(reason: result.errorOutput)
        }
    }

    public func eraseDevice(udid: String) async throws {
        let command = SimulatorCommand.erase(udid: udid)
        let result = try await executor.execute(command)
        if result.exitCode != 0 {
            throw SimulatorError.simctlFailed(reason: result.errorOutput)
        }
    }

    public func deleteDevice(udid: String) async throws {
        let command = SimulatorCommand.delete(udid: udid)
        let result = try await executor.execute(command)
        if result.exitCode != 0 {
            throw SimulatorError.simctlFailed(reason: result.errorOutput)
        }
    }

    public func createDevice(name: String, deviceType: String, runtime: String) async throws {
        let command = SimulatorCommand.create(name: name, deviceType: deviceType, runtime: runtime)
        let result = try await executor.execute(command)
        if result.exitCode != 0 {
            throw SimulatorError.simctlFailed(reason: result.errorOutput)
        }
    }

    public func installApplication(udid: String, appPath: String) async throws {
        let command = SimulatorCommand.installApp(udid: udid, appPath: appPath)
        let result = try await executor.execute(command)
        if result.exitCode != 0 {
            throw SimulatorError.simctlFailed(reason: result.errorOutput)
        }
    }

    public func uninstallApplication(udid: String, bundleID: String) async throws {
        let command = SimulatorCommand.uninstallApp(udid: udid, bundleID: bundleID)
        let result = try await executor.execute(command)
        if result.exitCode != 0 {
            throw SimulatorError.simctlFailed(reason: result.errorOutput)
        }
    }

    public func launchApplication(udid: String, bundleID: String, args: [String]) async throws {
        let command = SimulatorCommand.launchApp(udid: udid, bundleID: bundleID, args: args)
        let result = try await executor.execute(command)
        if result.exitCode != 0 {
            throw SimulatorError.simctlFailed(reason: result.errorOutput)
        }
    }

    public func terminateApplication(udid: String, bundleID: String) async throws {
        let command = SimulatorCommand.terminateApp(udid: udid, bundleID: bundleID)
        let result = try await executor.execute(command)
        if result.exitCode != 0 {
            throw SimulatorError.simctlFailed(reason: result.errorOutput)
        }
    }
}
