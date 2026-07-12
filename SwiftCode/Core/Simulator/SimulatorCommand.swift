import Foundation

public struct SimulatorCommand: Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let executable: String // e.g. "/usr/bin/xcrun" or "/usr/bin/xcode-select"
    public let arguments: [String]
    public let timeout: TimeInterval
    public let timestamp = Date()

    public init(name: String, executable: String, arguments: [String], timeout: TimeInterval = 60.0) {
        self.name = name
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
    }

    // Phase 4 command mappings:

    public static func determineDeveloperDirectory() -> SimulatorCommand {
        SimulatorCommand(name: "Determine Developer Directory", executable: "/usr/bin/xcode-select", arguments: ["-p"], timeout: 10.0)
    }

    public static func determineXcodeVersion() -> SimulatorCommand {
        SimulatorCommand(name: "Determine Xcode Version", executable: "/usr/bin/xcodebuild", arguments: ["-version"], timeout: 10.0)
    }

    public static func verifyXcrun() -> SimulatorCommand {
        SimulatorCommand(name: "Verify xcrun", executable: "/usr/bin/xcrun", arguments: ["--version"], timeout: 10.0)
    }

    public static func listRuntimes() -> SimulatorCommand {
        SimulatorCommand(name: "List Simulator Runtimes", executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "runtimes", "--json"], timeout: 20.0)
    }

    public static func listDevicesJSON() -> SimulatorCommand {
        SimulatorCommand(name: "List Simulator Devices", executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "--json"], timeout: 20.0)
    }

    public static func listDeviceTypes() -> SimulatorCommand {
        SimulatorCommand(name: "List Device Types", executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devicetypes", "--json"], timeout: 15.0)
    }

    public static func listPairs() -> SimulatorCommand {
        SimulatorCommand(name: "List Available Pairs", executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "pairs", "--json"], timeout: 15.0)
    }

    public static func listEverything() -> SimulatorCommand {
        SimulatorCommand(name: "List Everything", executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "--json"], timeout: 30.0)
    }

    // Legacy standard list devices:
    public static func listDevices() -> SimulatorCommand {
        SimulatorCommand(name: "List Devices", executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "-j"], timeout: 20.0)
    }

    // Core device control command mappings:

    public static func boot(udid: String) -> SimulatorCommand {
        SimulatorCommand(name: "Boot Device", executable: "/usr/bin/xcrun", arguments: ["simctl", "boot", udid], timeout: 30.0)
    }

    public static func shutdown(udid: String) -> SimulatorCommand {
        SimulatorCommand(name: "Shutdown Device", executable: "/usr/bin/xcrun", arguments: ["simctl", "shutdown", udid], timeout: 15.0)
    }

    public static func erase(udid: String) -> SimulatorCommand {
        SimulatorCommand(name: "Erase Device", executable: "/usr/bin/xcrun", arguments: ["simctl", "erase", udid], timeout: 20.0)
    }

    public static func delete(udid: String) -> SimulatorCommand {
        SimulatorCommand(name: "Delete Device", executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", udid], timeout: 15.0)
    }

    public static func create(name: String, deviceType: String, runtime: String) -> SimulatorCommand {
        SimulatorCommand(name: "Create Device", executable: "/usr/bin/xcrun", arguments: ["simctl", "create", name, deviceType, runtime], timeout: 20.0)
    }

    public static func installApp(udid: String, appPath: String) -> SimulatorCommand {
        SimulatorCommand(name: "Install App", executable: "/usr/bin/xcrun", arguments: ["simctl", "install", udid, appPath], timeout: 30.0)
    }

    public static func uninstallApp(udid: String, bundleID: String) -> SimulatorCommand {
        SimulatorCommand(name: "Uninstall App", executable: "/usr/bin/xcrun", arguments: ["simctl", "uninstall", udid, bundleID], timeout: 20.0)
    }

    public static func launchApp(udid: String, bundleID: String, args: [String] = []) -> SimulatorCommand {
        SimulatorCommand(name: "Launch App", executable: "/usr/bin/xcrun", arguments: ["simctl", "launch", udid, bundleID] + args, timeout: 20.0)
    }

    public static func terminateApp(udid: String, bundleID: String) -> SimulatorCommand {
        SimulatorCommand(name: "Terminate App", executable: "/usr/bin/xcrun", arguments: ["simctl", "terminate", udid, bundleID], timeout: 15.0)
    }
}
