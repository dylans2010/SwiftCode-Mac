import Foundation
import os.log

@MainActor
public final class ConnectGitService: @unchecked Sendable {
    public static let shared = ConnectGitService()
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectGitService")

    private init() {}

    public func registerHandlers() {
        ConnectServer.shared.registerHandler(for: .gitStatusRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.gitRead) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing git.read permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleGitStatusRequest(envelope: envelope, session: session)
        }

        ConnectServer.shared.registerHandler(for: .gitBranchesRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.gitRead) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing git.read permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleGitBranchesRequest(envelope: envelope, session: session)
        }
    }

    private func handleGitStatusRequest(envelope: MessageEnvelope, session: ConnectionSession) async {
        guard let project = ConnectServer.shared.workspaceProvider?.activeProject
                ?? ConnectUnavailableWorkspaceProvider.shared.activeProject else {
            ConnectServer.shared.sendError(code: "NO_ACTIVE_PROJECT", message: "No active project opened on Mac.", correlationID: envelope.messageID, on: session)
            return
        }

        do {
            let provider = ConnectServer.shared.workspaceProvider ?? ConnectUnavailableWorkspaceProvider.shared
            let status = try await provider.gitStatus(at: project.directoryURL)
            let payload = ConnectGitStatusResponsePayload(
                branch: status.branch,
                isClean: status.isClean,
                ahead: status.ahead,
                behind: status.behind,
                modifiedFiles: status.modifiedFiles,
                stagedFiles: status.stagedFiles,
                untrackedFiles: status.untrackedFiles
            )
            if let respEnv = try? MessageEnvelope.encode(payload: payload, type: .gitStatusResponse, correlationID: envelope.messageID) {
                try? session.send(envelope: respEnv)
            }
        } catch {
            ConnectServer.shared.sendError(code: "GIT_ERROR", message: error.localizedDescription, correlationID: envelope.messageID, on: session)
        }
    }

    private func handleGitBranchesRequest(envelope: MessageEnvelope, session: ConnectionSession) async {
        guard let project = ConnectServer.shared.workspaceProvider?.activeProject
                ?? ConnectUnavailableWorkspaceProvider.shared.activeProject else {
            ConnectServer.shared.sendError(code: "NO_ACTIVE_PROJECT", message: "No active project opened on Mac.", correlationID: envelope.messageID, on: session)
            return
        }

        do {
            let provider = ConnectServer.shared.workspaceProvider ?? ConnectUnavailableWorkspaceProvider.shared
            let branchNames = try await provider.gitBranches(at: project.directoryURL)
            if let respEnv = try? MessageEnvelope.encode(payload: ["branches": branchNames], type: .gitBranchesResponse, correlationID: envelope.messageID) {
                try? session.send(envelope: respEnv)
            }
        } catch {
            ConnectServer.shared.sendError(code: "GIT_ERROR", message: error.localizedDescription, correlationID: envelope.messageID, on: session)
        }
    }
}
