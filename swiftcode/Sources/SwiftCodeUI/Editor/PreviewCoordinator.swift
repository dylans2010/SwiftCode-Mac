import Foundation
import Observation
import SwiftCodePreviews

/// Named multi-session preview registry (Legacy
/// `SwiftCode/Core/Preview/PreviewCoordinator.swift`, Dylan's own
/// code, ported under MIT). The destination drove previews through
/// single-session controllers; this restores the registry:
/// `registerSession` / `removeSession` by id and the
/// `activeSessions` dictionary, with registration logged to
/// `PreviewDiagnostics`.

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
