import Foundation

public struct SimulatorCommand: Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let arguments: [String]
    public let timeout: TimeInterval
    public let timestamp = Date()

    public init(name: String, arguments: [String], timeout: TimeInterval = 60.0) {
        self.name = name
        self.arguments = arguments
        self.timeout = timeout
    }

    public static func listDevices() -> SimulatorCommand {
        SimulatorCommand(name: "List Devices", arguments: ["simctl", "list", "-j"])
    }

    public static func boot(udid: String) -> SimulatorCommand {
        SimulatorCommand(name: "Boot Device", arguments: ["simctl", "boot", udid])
    }

    public static func shutdown(udid: String) -> SimulatorCommand {
        SimulatorCommand(name: "Shutdown Device", arguments: ["simctl", "shutdown", udid], timeout: 15.0)
    }

    public static func erase(udid: String) -> SimulatorCommand {
        SimulatorCommand(name: "Erase Device", arguments: ["simctl", "erase", udid])
    }

    public static func delete(udid: String) -> SimulatorCommand {
        SimulatorCommand(name: "Delete Device", arguments: ["simctl", "delete", udid])
    }

    public static func create(name: String, deviceType: String, runtime: String) -> SimulatorCommand {
        SimulatorCommand(name: "Create Device", arguments: ["simctl", "create", name, deviceType, runtime])
    }

    public static func installApp(udid: String, appPath: String) -> SimulatorCommand {
        SimulatorCommand(name: "Install App", arguments: ["simctl", "install", udid, appPath])
    }

    public static func uninstallApp(udid: String, bundleID: String) -> SimulatorCommand {
        SimulatorCommand(name: "Uninstall App", arguments: ["simctl", "uninstall", udid, bundleID])
    }

    public static func launchApp(udid: String, bundleID: String, args: [String] = []) -> SimulatorCommand {
        SimulatorCommand(name: "Launch App", arguments: ["simctl", "launch", udid, bundleID] + args)
    }

    public static func terminateApp(udid: String, bundleID: String) -> SimulatorCommand {
        SimulatorCommand(name: "Terminate App", arguments: ["simctl", "terminate", udid, bundleID])
    }
}
