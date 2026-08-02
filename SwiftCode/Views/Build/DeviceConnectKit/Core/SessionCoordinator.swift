import Foundation
import OSLog

public actor SessionCoordinator {
    public static let shared = SessionCoordinator()
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "SessionCoordinator")

    private var activeSessions: [UUID: DeviceSession] = [:]
    private var pastSessions: [DeviceSession] = []

    private init() {}

    public func createSession(deviceUDID: String, deviceName: String, projectName: String, configuration: String) -> DeviceSession {
        let session = DeviceSession(
            deviceUDID: deviceUDID,
            deviceName: deviceName,
            projectName: projectName,
            configuration: configuration
        )
        activeSessions[session.id] = session
        return session
    }

    public func updateSession(_ session: DeviceSession) {
        activeSessions[session.id] = session
    }

    public func endSession(id: UUID, finalStatus: RuntimeStatus) -> DeviceSession? {
        guard var session = activeSessions[id] else { return nil }
        session.endTime = Date()
        session.runtimeStatus = finalStatus
        session.deploymentStatus = .completed
        activeSessions.removeValue(forKey: id)
        pastSessions.append(session)
        return session
    }

    public func getActiveSession(id: UUID) -> DeviceSession? {
        return activeSessions[id]
    }

    public func getAllPastSessions() -> [DeviceSession] {
        return pastSessions
    }
}
