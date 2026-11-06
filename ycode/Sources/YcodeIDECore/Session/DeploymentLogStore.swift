// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Services/LogManager.swift
// Adapted for Ycode: Legacy's LogManager, renamed DeploymentLogStore (its only job was deployment logs). DeploymentLogLine is defined here: Legacy defined it in Views/Deployments/DeploymentLogsView.swift (the Views slice), so it is re-declared locally rather than imported. ObservableObject -> @Observable.

import Foundation
import Observation

/// One line of deployment output. (Legacy defined this in
/// `Views/Deployments/DeploymentLogsView.swift`; it is declared here so the
/// store is self-contained.)
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

/// The deployment log. Legacy's `LogManager` existed only for this: a
/// single append-only list of deployment lines the Deploy UI reads.
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
