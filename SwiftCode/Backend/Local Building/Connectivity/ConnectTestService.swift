import Foundation
import os.log

@MainActor
public final class ConnectTestService: @unchecked Sendable {
    public static let shared = ConnectTestService()
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectTestService")

    private init() {}

    public func registerHandlers() {
        ConnectServer.shared.registerHandler(for: .testRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.testsExecute) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing tests.execute permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleTestRequest(envelope: envelope, session: session)
        }
    }

    private func handleTestRequest(envelope: MessageEnvelope, session: ConnectionSession) async {
        guard let project = ProjectSessionStore.shared.activeProject else {
            ConnectServer.shared.sendError(code: "NO_ACTIVE_PROJECT", message: "No active project available to test.", correlationID: envelope.messageID, on: session)
            return
        }

        let startedPayload = ["project": project.name]
        if let env = try? MessageEnvelope.encode(payload: startedPayload, type: .testStarted, correlationID: envelope.messageID) {
            ConnectServer.shared.broadcast(envelope: env, requiringPermission: .testsExecute)
        }

        let testTool = AssistTestRunnerTool()
        let builder = AssistContextBuilder(
            logger: AssistLogger(),
            permissions: AssistPermissionsManager(),
            memory: AssistMemoryGraph(),
            fileSystem: AssistFileSystem(workspaceRoot: project.directoryURL),
            git: AssistGitManager(project: project)
        )
        let context = builder.buildContext(sessionId: UUID())

        do {
            let result = try await testTool.execute(input: [:], context: context)
            let completedPayload = ConnectTestCompletedPayload(
                success: result.success,
                message: result.output
            )

            if let env = try? MessageEnvelope.encode(payload: completedPayload, type: .testCompleted, correlationID: envelope.messageID) {
                ConnectServer.shared.broadcast(envelope: env, requiringPermission: .testsExecute)
            }
        } catch {
            let completedPayload = ConnectTestCompletedPayload(
                success: false,
                message: error.localizedDescription
            )
            if let env = try? MessageEnvelope.encode(payload: completedPayload, type: .testCompleted, correlationID: envelope.messageID) {
                ConnectServer.shared.broadcast(envelope: env, requiringPermission: .testsExecute)
            }
        }
    }
}
