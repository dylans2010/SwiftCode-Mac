import Foundation

/// Defines preferences and setup paths for Apple Simulator management.
public struct SimulatorConfiguration: Codable, Sendable, Hashable {
    public var customSimctlPath: String?
    public var verboseLogging: Bool
    public var autoOpenSimulatorApp: Bool
    public var updateIntervalSeconds: Double

    public init(
        customSimctlPath: String? = nil,
        verboseLogging: Bool = false,
        autoOpenSimulatorApp: Bool = true,
        updateIntervalSeconds: Double = 5.0
    ) {
        self.customSimctlPath = customSimctlPath
        self.verboseLogging = verboseLogging
        self.autoOpenSimulatorApp = autoOpenSimulatorApp
        self.updateIntervalSeconds = updateIntervalSeconds
    }

    public static let `default` = SimulatorConfiguration()
}
