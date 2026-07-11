import Foundation

/// Represents an application installed inside a specific simulator device.
public struct SimulatorApplication: Identifiable, Sendable, Hashable, Codable {
    public var id: String { bundleIdentifier }

    public let bundleIdentifier: String
    public let name: String
    public let version: String?
    public let build: String?
    public let bundlePath: String
    public let sandboxPath: String?

    public init(
        bundleIdentifier: String,
        name: String,
        version: String? = nil,
        build: String? = nil,
        bundlePath: String,
        sandboxPath: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.build = build
        self.bundlePath = bundlePath
        self.sandboxPath = sandboxPath
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }

    public static func == (lhs: SimulatorApplication, rhs: SimulatorApplication) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}
