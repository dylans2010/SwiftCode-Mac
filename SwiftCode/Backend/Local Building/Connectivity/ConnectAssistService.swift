import Foundation
import os.log

@MainActor
public final class ConnectAssistService: @unchecked Sendable {
    public static let shared = ConnectAssistService()
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectAssistService")

    private init() {}

    public func registerHandlers() {
        ConnectServer.shared.registerHandler(for: .assistQueryRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.assistUse) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing assist.use permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleAssistQuery(envelope: envelope, session: session)
        }
    }

    private func handleAssistQuery(envelope: MessageEnvelope, session: ConnectionSession) async {
        guard let payload = try? envelope.decodePayload(ConnectAssistQueryRequestPayload.self) else {
            ConnectServer.shared.sendError(code: "BAD_REQUEST", message: "Invalid assist query payload.", correlationID: envelope.messageID, on: session)
            return
        }

        guard let project = ProjectSessionStore.shared.activeProject else {
            ConnectServer.shared.sendError(code: "NO_ACTIVE_PROJECT", message: "No active project context available.", correlationID: envelope.messageID, on: session)
            return
        }

        let answer = "Assist on Mac context for project '\(project.name)': Prompt received: '\(payload.prompt)'"
        let responsePayload = ConnectAssistResponsePayload(answer: answer, suggestedActions: ["Build Project", "Run Tests"])
        if let respEnv = try? MessageEnvelope.encode(payload: responsePayload, type: .assistResponse, correlationID: envelope.messageID) {
            try? session.send(envelope: respEnv)
        }
    }
}
