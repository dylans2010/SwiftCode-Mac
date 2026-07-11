import Foundation

/// Represents an Apple Simulator device.
public struct SimulatorDevice: Identifiable, Sendable, Hashable, Codable {
    public var id: String { udid }

    public let udid: String
    public let name: String
    public let deviceTypeIdentifier: String?
    public let state: SimulatorState
    public let isAvailable: Bool
    public let availabilityError: String?
    public var runtimeIdentifier: String?

    public init(
        udid: String,
        name: String,
        deviceTypeIdentifier: String? = nil,
        state: SimulatorState,
        isAvailable: Bool = true,
        availabilityError: String? = nil,
        runtimeIdentifier: String? = nil
    ) {
        self.udid = udid
        self.name = name
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.state = state
        self.isAvailable = isAvailable
        self.availabilityError = availabilityError
        self.runtimeIdentifier = runtimeIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(udid)
    }

    public static func == (lhs: SimulatorDevice, rhs: SimulatorDevice) -> Bool {
        lhs.udid == rhs.udid
    }
}
