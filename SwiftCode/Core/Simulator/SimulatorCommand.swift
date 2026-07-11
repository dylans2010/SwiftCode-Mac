import Foundation

/// Represents a command to execute via Apple's simulator developer utilities.
public enum SimulatorCommand: Sendable, Hashable {
    case boot(udid: String)
    case shutdown(udid: String)
    case erase(udid: String)
    case delete(udid: String)
    case install(udid: String, appPath: String)
    case launch(udid: String, bundleID: String, arguments: [String] = [])
    case terminate(udid: String, bundleID: String)
    case createDevice(name: String, deviceType: String, runtime: String)
    case openSimulatorApp

    public var displayTitle: String {
        switch self {
        case .boot: return "Boot Device"
        case .shutdown: return "Shut Down Device"
        case .erase: return "Erase Device"
        case .delete: return "Delete Device"
        case .install: return "Install Application"
        case .launch: return "Launch Application"
        case .terminate: return "Terminate Application"
        case .createDevice: return "Create Device"
        case .openSimulatorApp: return "Open Simulator App"
        }
    }
}
