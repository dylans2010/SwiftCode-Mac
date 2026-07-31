import Foundation
import Observation

@Observable
@MainActor
public final class PreviewCoordinator {
    public static let shared = PreviewCoordinator()

    public private(set) var activeSessions: [String: PreviewSession] = [:]
    private init() {}

    public func registerSession(_ session: PreviewSession) {
        activeSessions[session.sessionID] = session
        PreviewDiagnostics.shared.addLog(category: "render", message: "Registered session '\(session.sessionID)' for target: \(session.targetViewName)")
    }

    public func removeSession(id: String) {
        activeSessions.removeValue(forKey: id)
    }
}
