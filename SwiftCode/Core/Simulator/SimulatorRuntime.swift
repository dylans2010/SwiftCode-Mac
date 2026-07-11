import Foundation

/// Represents a platform runtime in the Apple simulator environment.
public struct SimulatorRuntime: Identifiable, Sendable, Hashable, Codable {
    public var id: String { identifier }

    public let identifier: String
    public let name: String
    public let version: String
    public let buildversion: String
    public let platform: String
    public let isAvailable: Bool

    public init(
        identifier: String,
        name: String,
        version: String,
        buildversion: String,
        platform: String,
        isAvailable: Bool = true
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.buildversion = buildversion
        self.platform = platform
        self.isAvailable = isAvailable
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    public static func == (lhs: SimulatorRuntime, rhs: SimulatorRuntime) -> Bool {
        lhs.identifier == rhs.identifier
    }
}
