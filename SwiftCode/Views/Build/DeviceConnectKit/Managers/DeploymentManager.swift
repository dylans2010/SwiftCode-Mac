import Foundation
import Observation

@Observable
@MainActor
public final class DeploymentManager {
    public static let shared = DeploymentManager()

    public private(set) var deploymentStatus: DeploymentStatus = .idle
    public private(set) var currentStageDescription = "Idle"
    public private(set) var isDeploying = false
    public private(set) var logs: [DeviceLog] = []

    private init() {}

    public func startDeployment(
        device: ConnectedDevice,
        projectName: String,
        projectPath: String,
        scheme: String,
        appBundleURL: URL,
        bundleIdentifier: String
    ) async {
        guard !isDeploying else { return }
        isDeploying = true
        logs.removeAll()

        let session = SessionManager.shared.createSession(
            device: device,
            projectName: projectName,
            configuration: "Debug"
        )

        let success = await DeviceConnectEngine.shared.deploy(
            device: device,
            projectName: projectName,
            projectPath: projectPath,
            scheme: scheme,
            appBundleURL: appBundleURL,
            bundleIdentifier: bundleIdentifier,
            onStateUpdate: { [weak self] status, desc in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.deploymentStatus = status
                    self.currentStageDescription = desc

                    var updatedSession = session
                    updatedSession.deploymentStatus = status
                    if status == .running {
                        updatedSession.runtimeStatus = .running
                    } else if status == .completed {
                        updatedSession.endTime = Date()
                    } else if status == .failed {
                        updatedSession.endTime = Date()
                        updatedSession.buildStatus = .failed
                    }
                    SessionManager.shared.updateActiveSession(updatedSession)

                    if status == .completed || status == .failed || status == .cancelled {
                        self.isDeploying = false
                        let historyItem = DeploymentHistory(
                            projectName: projectName,
                            deviceName: device.name,
                            deviceUDID: device.udid,
                            duration: Date().timeIntervalSince(session.startTime),
                            buildResult: status == .failed ? .failed : .succeeded,
                            deployResult: status,
                            runResult: status == .completed ? .running : .idle
                        )
                        HistoryManager.shared.addHistoryItem(historyItem)
                    }
                }
            },
            onLogUpdate: { [weak self] logLine in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let parsedLog = LogParser.parseLogLine(logLine, type: .build)
                    self.logs.append(parsedLog)
                    ConsoleManager.shared.appendLog(parsedLog)
                }
            }
        )

        if success {
            NotificationService.shared.postNotification(
                title: "Deployment Successful",
                subtitle: device.name,
                body: "Successfully deployed and launched \(projectName)."
            )
        } else {
            NotificationService.shared.postNotification(
                title: "Deployment Failed",
                subtitle: device.name,
                body: "Failed to deploy \(projectName). Please check build logs."
            )
        }
    }
}
