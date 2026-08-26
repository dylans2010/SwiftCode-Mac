import Foundation
import os.log

public enum BuildState: String, Codable, Sendable {
    case idle
    case preparing
    case building
    case succeeded
    case failed
    case cancelled
}

@Observable
@MainActor
public final class ConnectBuildService: @unchecked Sendable {
    public static let shared = ConnectBuildService()

    public private(set) var currentBuildState: BuildState = .idle
    private var activeBuildTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectBuildService")

    private init() {}

    public func registerHandlers() {
        ConnectServer.shared.registerHandler(for: .buildRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.buildExecute) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing build.execute permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleBuildRequest(envelope: envelope, session: session)
        }

        ConnectServer.shared.registerHandler(for: .cancelBuildRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.buildExecute) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing build.execute permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.cancelActiveBuild(correlationID: envelope.messageID)
        }
    }

    public func handleBuildRequest(envelope: MessageEnvelope, session: ConnectionSession) async {
        guard currentBuildState != .building else {
            ConnectServer.shared.sendError(code: "BUILD_IN_PROGRESS", message: "A build is already in progress.", correlationID: envelope.messageID, on: session)
            return
        }

        guard let project = ProjectSessionStore.shared.activeProject else {
            ConnectServer.shared.sendError(code: "NO_ACTIVE_PROJECT", message: "No active project available to build.", correlationID: envelope.messageID, on: session)
            return
        }

        let requestPayload = (try? envelope.decodePayload(ConnectBuildRequestPayload.self)) ?? ConnectBuildRequestPayload()
        let scheme = requestPayload.scheme ?? project.ciBuildConfiguration?.schemeName ?? project.name

        currentBuildState = .preparing

        // Send Build Started event to connected sessions
        let startedPayload = ["project": project.name, "scheme": scheme]
        if let env = try? MessageEnvelope.encode(payload: startedPayload, type: .buildStarted, correlationID: envelope.messageID) {
            ConnectServer.shared.broadcast(envelope: env, requiringPermission: .buildExecute)
        }

        activeBuildTask = Task {
            let startTime = Date()
            self.currentBuildState = .building

            // Stream build progress
            let progress1 = ConnectBuildProgressPayload(phase: "Preparing dependencies", completedSteps: 1, totalSteps: 4, message: "Validating environment")
            if let env = try? MessageEnvelope.encode(payload: progress1, type: .buildProgress, correlationID: envelope.messageID) {
                ConnectServer.shared.broadcast(envelope: env, requiringPermission: .buildExecute)
            }

            do {
                let result = await XcodeBuildAPI.shared.buildProject()
                let success = (result.status == .succeeded)

                let duration = Date().timeIntervalSince(startTime)

                if success {
                    self.currentBuildState = .succeeded
                    let completed = ConnectBuildCompletedPayload(success: true, duration: duration, errorCount: 0, warningCount: 0)
                    if let env = try? MessageEnvelope.encode(payload: completed, type: .buildCompleted, correlationID: envelope.messageID) {
                        ConnectServer.shared.broadcast(envelope: env, requiringPermission: .buildExecute)
                    }
                } else {
                    self.currentBuildState = .failed
                    let diag = ConnectBuildDiagnosticPayload(severity: "error", message: "Build failed during compilation.")
                    if let envDiag = try? MessageEnvelope.encode(payload: diag, type: .buildDiagnostic, correlationID: envelope.messageID) {
                        ConnectServer.shared.broadcast(envelope: envDiag, requiringPermission: .buildExecute)
                    }

                    let completed = ConnectBuildCompletedPayload(success: false, duration: duration, errorCount: 1, warningCount: 0)
                    if let env = try? MessageEnvelope.encode(payload: completed, type: .buildCompleted, correlationID: envelope.messageID) {
                        ConnectServer.shared.broadcast(envelope: env, requiringPermission: .buildExecute)
                    }
                }
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                self.currentBuildState = .failed

                let diag = ConnectBuildDiagnosticPayload(severity: "error", message: error.localizedDescription)
                if let envDiag = try? MessageEnvelope.encode(payload: diag, type: .buildDiagnostic, correlationID: envelope.messageID) {
                    ConnectServer.shared.broadcast(envelope: envDiag, requiringPermission: .buildExecute)
                }

                let completed = ConnectBuildCompletedPayload(success: false, duration: duration, errorCount: 1, warningCount: 0)
                if let env = try? MessageEnvelope.encode(payload: completed, type: .buildCompleted, correlationID: envelope.messageID) {
                    ConnectServer.shared.broadcast(envelope: env, requiringPermission: .buildExecute)
                }
            }
        }
    }

    public func cancelActiveBuild(correlationID: String?) async {
        guard currentBuildState == .building || currentBuildState == .preparing else { return }
        activeBuildTask?.cancel()
        activeBuildTask = nil
        currentBuildState = .cancelled
        logger.info("Active build cancelled by request.")

        let completed = ConnectBuildCompletedPayload(success: false, duration: 0, errorCount: 0, warningCount: 0)
        if let env = try? MessageEnvelope.encode(payload: completed, type: .buildCompleted, correlationID: correlationID) {
            ConnectServer.shared.broadcast(envelope: env, requiringPermission: .buildExecute)
        }
    }
}
