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
        let store = ProjectSessionStore.shared
        let activeProjectInfo: ConnectProjectInfo?

        if let p = store.activeProject {
            activeProjectInfo = ConnectProjectInfo(
                id: p.id.uuidString,
                name: p.name,
                path: p.directoryURL.path,
                activeScheme: p.ciBuildConfiguration?.schemeName ?? p.name,
                activeTarget: p.name,
                destinations: p.destinations ?? ["macOS"],
                swiftVersion: ProjectRegistryManager.shared.registryEntries[p.id.uuidString]?.swiftVersion ?? "5.9"
            )
        } else {
            activeProjectInfo = nil
        }

        let available = store.projects.map { p in
            ConnectProjectInfo(
                id: p.id.uuidString,
                name: p.name,
                path: p.directoryURL.path,
                activeScheme: p.ciBuildConfiguration?.schemeName ?? p.name,
                activeTarget: p.name,
                destinations: p.destinations ?? ["macOS"],
                swiftVersion: ProjectRegistryManager.shared.registryEntries[p.id.uuidString]?.swiftVersion ?? "5.9"
            )
        }

        let payload = ConnectProjectResponsePayload(activeProject: activeProjectInfo, availableProjects: available)
        if let respEnv = try? MessageEnvelope.encode(payload: payload, type: .projectResponse, correlationID: envelope.messageID) {
            try? session.send(envelope: respEnv)
        }
    }
}
