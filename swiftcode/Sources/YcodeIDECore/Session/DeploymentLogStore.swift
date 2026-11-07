import Foundation
import Observation

public struct DeploymentLogLine: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let isError: Bool

    public init(timestamp: Date, message: String, isError: Bool) {
        self.timestamp = timestamp
        self.message = message
        self.isError = isError
    }
}

@Observable
@MainActor
public final class DeploymentLogStore: Sendable {
    public static let shared = DeploymentLogStore()

    public var deploymentLogs: [DeploymentLogLine] = []

    private init() {}

    public func logDeployment(_ message: String, isError: Bool = false) {
        deploymentLogs.append(DeploymentLogLine(timestamp: Date(), message: message, isError: isError))
    }

    public func clearDeploymentLogs() {
        deploymentLogs = []
    }
}
