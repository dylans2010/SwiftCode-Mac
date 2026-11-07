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

        guard let project = ConnectServer.shared.workspaceProvider?.activeProject
                ?? ConnectUnavailableWorkspaceProvider.shared.activeProject else {
            ConnectServer.shared.sendError(code: "NO_ACTIVE_PROJECT", message: "No active project for terminal execution.", correlationID: envelope.messageID, on: session)
            return
        }

        let isDangerous = payload.command.contains("rm ") || payload.command.contains("sudo ") || payload.command.contains("git reset --hard")
        if isDangerous {
            logger.warning("Remote terminal command from \(session.deviceName ?? "iOS") looks destructive: \(payload.command)")
        }

        var workingDirectory = project.directoryURL
        if let requested = payload.workingDirectory, !requested.isEmpty {
            let candidate = project.directoryURL.appendingPathComponent(requested).standardizedFileURL
            let root = project.directoryURL.standardizedFileURL
            if candidate.path.hasPrefix(root.path + "/") || candidate.path == root.path {
                workingDirectory = candidate
            } else {
                ConnectServer.shared.sendError(code: "ACCESS_DENIED", message: "Working directory outside project boundaries is forbidden.", correlationID: envelope.messageID, on: session)
                return
            }
        }

        let (output, exitCode) = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", payload.command]
            process.currentDirectoryURL = workingDirectory
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
            } catch {
                return (error.localizedDescription, 1)
            }
            process.waitUntilExit()
            let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return (out + err, Int(process.terminationStatus))
        }.value

        let outputPayload = ConnectTerminalOutputPayload(output: output, isError: exitCode != 0)
        if let respEnv = try? MessageEnvelope.encode(payload: outputPayload, type: .terminalOutput, correlationID: envelope.messageID) {
            try? session.send(envelope: respEnv)
        }
        if let exitEnv = try? MessageEnvelope.encode(payload: ["exitCode": "\(exitCode)"], type: .terminalExit, correlationID: envelope.messageID) {
            try? session.send(envelope: exitEnv)
        }
    }
}
