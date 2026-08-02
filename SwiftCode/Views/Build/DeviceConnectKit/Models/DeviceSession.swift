import Foundation

public struct DeviceSession: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let deviceUDID: String
    public let deviceName: String
    public let projectName: String
    public let configuration: String // Debug, Release
    public let startTime: Date
    public var endTime: Date?

    // Statuses
    public var buildStatus: BuildStatus
    public var deploymentStatus: DeploymentStatus
    public var runtimeStatus: RuntimeStatus
    public var signingStatus: SigningStatus

    // Durations and Metrics
    public var buildDuration: TimeInterval
    public var installDuration: TimeInterval
    public var launchDuration: TimeInterval
    public var totalDuration: TimeInterval {
        if let end = endTime {
            return end.timeIntervalSince(startTime)
        }
        return Date().timeIntervalSince(startTime)
    }

    // Logs and Diagnostics
    public var buildLogs: String
    public var runtimeLogs: String
    public var errors: [String]
    public var warnings: [String]
    public var suggestions: [String]

    public init(
        id: UUID = UUID(),
        deviceUDID: String,
        deviceName: String,
        projectName: String,
        configuration: String = "Debug",
        startTime: Date = Date(),
        endTime: Date? = nil,
        buildStatus: BuildStatus = .idle,
        deploymentStatus: DeploymentStatus = .idle,
        runtimeStatus: RuntimeStatus = .idle,
        signingStatus: SigningStatus = .idle,
        buildDuration: TimeInterval = 0,
        installDuration: TimeInterval = 0,
        launchDuration: TimeInterval = 0,
        buildLogs: String = "",
        runtimeLogs: String = "",
        errors: [String] = [],
        warnings: [String] = [],
        suggestions: [String] = []
    ) {
        self.id = id
        self.deviceUDID = deviceUDID
        self.deviceName = deviceName
        self.projectName = projectName
        self.configuration = configuration
        self.startTime = startTime
        self.endTime = endTime
        self.buildStatus = buildStatus
        self.deploymentStatus = deploymentStatus
        self.runtimeStatus = runtimeStatus
        self.signingStatus = signingStatus
        self.buildDuration = buildDuration
        self.installDuration = installDuration
        self.launchDuration = launchDuration
        self.buildLogs = buildLogs
        self.runtimeLogs = runtimeLogs
        self.errors = errors
        self.warnings = warnings
        self.suggestions = suggestions
    }
}
