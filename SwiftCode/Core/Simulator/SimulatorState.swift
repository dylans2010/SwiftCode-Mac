import Foundation

/// Represents the execution state of a Simulator.
public enum SimulatorState: String, Sendable, Codable, CaseIterable {
    case booted = "Booted"
    case shutdown = "Shutdown"
    case booting = "Booting"
    case shuttingDown = "Shutting Down"
    case unknown = "Unknown"

    public var isRunning: Bool {
        self == .booted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawString = try container.decode(String.self)
        // Normalize casing differences
        let normalized = rawString.lowercased().replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "booted":
            self = .booted
        case "shutdown", "off":
            self = .shutdown
        case "booting":
            self = .booting
        case "shuttingdown":
            self = .shuttingDown
        default:
            self = .unknown
        }
    }
}
