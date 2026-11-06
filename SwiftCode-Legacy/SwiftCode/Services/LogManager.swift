import Foundation
import Combine

@MainActor
final class LogManager: ObservableObject {
    static let shared = LogManager()

    @Published var deploymentLogs: [DeploymentLogLine] = []

    private init() {}

    func logDeployment(_ message: String, isError: Bool = false) {
        deploymentLogs.append(DeploymentLogLine(timestamp: Date(), message: message, isError: isError))
    }

    func clearDeploymentLogs() {
        deploymentLogs = []
    }
}
