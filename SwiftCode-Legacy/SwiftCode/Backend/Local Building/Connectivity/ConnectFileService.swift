import Foundation
import os.log

@MainActor
public final class ConnectFileService: @unchecked Sendable {
    public static let shared = ConnectFileService()
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectFileService")

    private init() {}

    public func registerHandlers() {
        ConnectServer.shared.registerHandler(for: .fileListRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.filesRead) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing files.read permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleFileListRequest(envelope: envelope, session: session)
        }

        ConnectServer.shared.registerHandler(for: .fileReadRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.filesRead) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing files.read permission.", correlationID: envelope.messageID, on: session)
                return
            }
            await self?.handleFileReadRequest(envelope: envelope, session: session)
        }
    }

    private func handleFileListRequest(envelope: MessageEnvelope, session: ConnectionSession) async {
        guard let project = ProjectSessionStore.shared.activeProject else {
            ConnectServer.shared.sendError(code: "NO_ACTIVE_PROJECT", message: "No active project available.", correlationID: envelope.messageID, on: session)
            return
        }

        let items = project.files.map { node in
            ConnectFileItem(path: node.path, name: node.name, isDirectory: node.isDirectory)
        }

        let payload = ConnectFileListResponsePayload(files: items)
        if let respEnv = try? MessageEnvelope.encode(payload: payload, type: .fileListResponse, correlationID: envelope.messageID) {
            try? session.send(envelope: respEnv)
        }
    }

    private func handleFileReadRequest(envelope: MessageEnvelope, session: ConnectionSession) async {
        guard let project = ProjectSessionStore.shared.activeProject else {
            ConnectServer.shared.sendError(code: "NO_ACTIVE_PROJECT", message: "No active project available.", correlationID: envelope.messageID, on: session)
            return
        }

        guard let payload = try? envelope.decodePayload([String: String].self),
              let relativePath = payload["path"] else {
            ConnectServer.shared.sendError(code: "BAD_REQUEST", message: "Missing file path parameter.", correlationID: envelope.messageID, on: session)
            return
        }

        // Prevent path traversal attacks (e.g. ../../)
        guard !relativePath.contains("..") else {
            ConnectServer.shared.sendError(code: "INVALID_PATH", message: "Path traversal is strictly prohibited.", correlationID: envelope.messageID, on: session)
            return
        }

        let fileURL = project.directoryURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootURL = project.directoryURL.standardizedFileURL
        guard fileURL.path.hasPrefix(rootURL.path + "/") || fileURL.path == rootURL.path else {
            ConnectServer.shared.sendError(code: "ACCESS_DENIED", message: "File access outside project boundaries is forbidden.", correlationID: envelope.messageID, on: session)
            return
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let responsePayload = ["path": relativePath, "content": content]
            if let respEnv = try? MessageEnvelope.encode(payload: responsePayload, type: .fileReadResponse, correlationID: envelope.messageID) {
                try? session.send(envelope: respEnv)
            }
        } catch {
            ConnectServer.shared.sendError(code: "READ_FAILED", message: error.localizedDescription, correlationID: envelope.messageID, on: session)
        }
    }
}
