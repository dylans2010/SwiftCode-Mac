import Foundation

public enum SimulatorState: String, Codable, Sendable {
    case shutdown = "Shutdown"
    case booting = "Booting"
    case booted = "Booted"
    case launchingSimulator = "Launching Simulator"
    case ready = "Ready"
    case failed = "Failed"
    case shuttingDown = "Shutting Down"
    case erasing = "Erasing"
    case unknown = "Unknown"

    public var isRunning: Bool {
        self == .booted || self == .booting || self == .launchingSimulator || self == .ready
    }
}
