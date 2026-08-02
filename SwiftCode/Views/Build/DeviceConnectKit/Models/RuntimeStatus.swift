import Foundation

public enum RuntimeStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case idle = "Not Running"
    case launching = "Launching"
    case running = "Running"
    case terminated = "Terminated"
    case crashed = "Crashed"
    case disconnected = "Disconnected"

    public var description: String {
        return self.rawValue
    }
}
