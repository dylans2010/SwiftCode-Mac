import Foundation

public struct SimulatorDevice: Identifiable, Hashable, Codable, Sendable {
    public var id: String { udid }
    public let udid: String
    public let name: String
    public let runtimeIdentifier: String
    public let platform: String
    public let osVersion: String
    public let architecture: String
    public var state: SimulatorState
    public let isAvailable: Bool
    public let dateCreated: Date

    public init(
        udid: String,
        name: String,
        runtimeIdentifier: String,
        platform: String,
        osVersion: String,
        architecture: String,
        state: SimulatorState,
        isAvailable: Bool = true,
        dateCreated: Date = Date()
    ) {
        self.udid = udid
        self.name = name
        self.runtimeIdentifier = runtimeIdentifier
        self.platform = platform
        self.osVersion = osVersion
        self.architecture = architecture
        self.state = state
        self.isAvailable = isAvailable
        self.dateCreated = dateCreated
    }
}
