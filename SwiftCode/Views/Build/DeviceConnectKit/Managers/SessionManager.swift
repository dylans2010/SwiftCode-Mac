import Foundation
import Observation

@Observable
@MainActor
public final class SessionManager {
    public static let shared = SessionManager()

    public private(set) var activeSession: DeviceSession?
    public private(set) var sessionsHistory: [DeviceSession] = []

    private init() {}

    public func createSession(device: ConnectedDevice, projectName: String, configuration: String) -> DeviceSession {
        let session = DeviceSession(
            deviceUDID: device.udid,
            deviceName: device.name,
            projectName: projectName,
            configuration: configuration
        )
        activeSession = session
        sessionsHistory.append(session)
        return session
    }

    public func updateActiveSession(_ session: DeviceSession) {
        self.activeSession = session
        if let idx = sessionsHistory.firstIndex(where: { $0.id == session.id }) {
            sessionsHistory[idx] = session
        } else {
            sessionsHistory.append(session)
        }
    }

    public func endActiveSession(finalStatus: RuntimeStatus) {
        guard var session = activeSession else { return }
        session.endTime = Date()
        session.runtimeStatus = finalStatus
        session.deploymentStatus = .completed
        updateActiveSession(session)
        activeSession = nil
    }

    public func clearHistory() {
        sessionsHistory.removeAll()
    }
}
