import Foundation

public struct DeploymentHistory: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let projectName: String
    public let deviceName: String
    public let deviceUDID: String
    public let timestamp: Date
    public let duration: TimeInterval
    public let buildResult: BuildStatus
    public let deployResult: DeploymentStatus
    public let runResult: RuntimeStatus

    public init(
        id: UUID = UUID(),
        projectName: String,
        deviceName: String,
        deviceUDID: String,
        timestamp: Date = Date(),
        duration: TimeInterval,
        buildResult: BuildStatus,
        deployResult: DeploymentStatus,
        runResult: RuntimeStatus
    ) {
        self.id = id
        self.projectName = projectName
        self.deviceName = deviceName
        self.deviceUDID = deviceUDID
        self.timestamp = timestamp
        self.duration = duration
        self.buildResult = buildResult
        self.deployResult = deployResult
        self.runResult = runResult
    }
}
