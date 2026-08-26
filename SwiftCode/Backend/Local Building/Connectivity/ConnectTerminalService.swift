import Foundation
import os.log

@MainActor
public final class ConnectTerminalService: @unchecked Sendable {
    public static let shared = ConnectTerminalService()
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectTerminalService")

    private init() {}

    public func registerHandlers() {
        ConnectServer.shared.registerHandler(for: .terminalExecuteRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.terminalExecute) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing terminal.execute permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleTerminalRequest(envelope: envelope, session: session)
        }
    }

    private func handleTerminalRequest(envelope: MessageEnvelope, session: ConnectionSession) async {
        guard let payload = try? envelope.decodePayload(ConnectTerminalExecuteRequestPayload.self) else {
            ConnectServer.shared.sendError(code: "BAD_REQUEST", message: "Invalid terminal execution payload.", correlationID: envelope.messageID, on: session)
            return
        }

        guard let project = ProjectSessionStore.shared.activeProject else {
            ConnectServer.shared.sendError(code: "NO_ACTIVE_PROJECT", message: "No active project for terminal execution.", correlationID: envelope.messageID, on: session)
            return
        }

        let isDangerous = payload.command.contains("rm ") || payload.command.contains("sudo ") || payload.command.contains("git reset --hard")

        let termTool = UseTermFunction()
        let context = AssistContext(workspaceRoot: project.directoryURL, logger: AssistLogger(category: "ConnectTerminalService"))

        let input: [String: Any] = [
            "command": payload.command,
            "workingDirectory": payload.workingDirectory ?? "",
            "explanation": "Remote terminal command from SwiftCode Connect device (\(session.deviceName ?? "iOS"))",
            "estimatedImpact": isDangerous ? "High: Potential file deletion or destructive modification" : "Low: Shell command execution",
            "modifiesRepo": isDangerous ? "true" : "false"
        ]

        do {
            let result = try await termTool.execute(input: input, context: context)

            let outputPayload = ConnectTerminalOutputPayload(output: result.message, isError: !result.isSuccess)
            if let respEnv = try? MessageEnvelope.encode(payload: outputPayload, type: .terminalOutput, correlationID: envelope.messageID) {
                try? session.send(envelope: respEnv)
            }
            if let exitEnv = try? MessageEnvelope.encode(payload: ["exitCode": result.isSuccess ? 0 : 1], type: .terminalExit, correlationID: envelope.messageID) {
                try? session.send(envelope: exitEnv)
            }
        } catch {
            let outputPayload = ConnectTerminalOutputPayload(output: error.localizedDescription, isError: true)
            if let respEnv = try? MessageEnvelope.encode(payload: outputPayload, type: .terminalOutput, correlationID: envelope.messageID) {
                try? session.send(envelope: respEnv)
            }
            if let exitEnv = try? MessageEnvelope.encode(payload: ["exitCode": 1], type: .terminalExit, correlationID: envelope.messageID) {
                try? session.send(envelope: exitEnv)
            }
        }
    }
}
