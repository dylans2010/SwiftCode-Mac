// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Local Building/Connectivity/ConnectProjectService.swift
// Adapted for SwiftCode: ProjectSessionStore/ProjectRegistryManager replaced by the ConnectWorkspaceProvider seam.

import Foundation
import os.log

@MainActor
public final class ConnectProjectService: @unchecked Sendable {
    public static let shared = ConnectProjectService()
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectProjectService")

    private init() {}

    public func registerHandlers() {
        ConnectServer.shared.registerHandler(for: .projectRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.projectRead) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing project.read permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleProjectRequest(envelope: envelope, session: session)
        }
    }

    private func handleProjectRequest(envelope: MessageEnvelope, session: ConnectionSession) async {
        let provider = ConnectServer.shared.workspaceProvider ?? ConnectUnavailableWorkspaceProvider.shared
        let activeProjectInfo = provider.activeProject?.connectProjectInfo
        let available = provider.availableProjects.map { $0.connectProjectInfo }

        let payload = ConnectProjectResponsePayload(activeProject: activeProjectInfo, availableProjects: available)
        if let respEnv = try? MessageEnvelope.encode(payload: payload, type: .projectResponse, correlationID: envelope.messageID) {
            try? session.send(envelope: respEnv)
        }
    }
}
