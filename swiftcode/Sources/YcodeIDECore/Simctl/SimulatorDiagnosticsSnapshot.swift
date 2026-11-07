import Foundation

public struct SimulatorDiagnosticsSnapshot: Sendable {
    public let developerDirectory: String?
    public let xcodeVersion: String?
    public let xcrunLocation: String?
    public let simctlAvailable: Bool
    public let runtimeCount: Int
    public let deviceCount: Int
    public let runningSimulatorCount: Int
    public let lastRefreshDate: Date?
    public let lastDiscoveryDuration: Duration?
    public let recentCommands: [CommandExecutionRecord]

    public init(
        developerDirectory: String?,
        xcodeVersion: String?,
        xcrunLocation: String?,
        simctlAvailable: Bool,
        runtimeCount: Int,
        deviceCount: Int,
        runningSimulatorCount: Int,
        lastRefreshDate: Date?,
        lastDiscoveryDuration: Duration?,
        recentCommands: [CommandExecutionRecord]
    ) {
        self.developerDirectory = developerDirectory
        self.xcodeVersion = xcodeVersion
        self.xcrunLocation = xcrunLocation
        self.simctlAvailable = simctlAvailable
        self.runtimeCount = runtimeCount
        self.deviceCount = deviceCount
        self.runningSimulatorCount = runningSimulatorCount
        self.lastRefreshDate = lastRefreshDate
        self.lastDiscoveryDuration = lastDiscoveryDuration
        self.recentCommands = recentCommands
    }

    public static let initial = SimulatorDiagnosticsSnapshot(
        developerDirectory: nil,
        xcodeVersion: nil,
        xcrunLocation: nil,
        simctlAvailable: false,
        runtimeCount: 0,
        deviceCount: 0,
        runningSimulatorCount: 0,
        lastRefreshDate: nil,
        lastDiscoveryDuration: nil,
        recentCommands: []
    )
}
