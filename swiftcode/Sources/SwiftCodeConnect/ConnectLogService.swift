import Foundation
import os.log

@MainActor
public final class ConnectLogService: @unchecked Sendable {
    public static let shared = ConnectLogService()

    private var subscribedSessions: Set<UUID> = []
    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectLogService")

    private init() {}

    public func registerHandlers() {
        ConnectServer.shared.registerHandler(for: .logsSubscribeRequest) { [weak self] envelope, session in
            guard session.grantedPermissions.contains(.logsRead) else {
                ConnectServer.shared.sendError(code: "PERMISSION_DENIED", message: "Missing logs.read permission.", correlationID: envelope.messageID, on: session)
                return
            }
            self?.subscribedSessions.insert(session.id)
            if let resp = try? MessageEnvelope.encode(payload: ["subscribed": true], type: .logEvent, correlationID: envelope.messageID) {
                try? session.send(envelope: resp)
            }
        }

        ConnectServer.shared.registerHandler(for: .logsUnsubscribeRequest) { [weak self] _, session in
            self?.subscribedSessions.remove(session.id)
        }
    }

    public func emitLog(level: String, category: String, message: String) {
        let payload = ConnectLogEventPayload(timestamp: Date(), level: level, category: category, message: message)
        guard let env = try? MessageEnvelope.encode(payload: payload, type: .logEvent) else { return }

        for session in ConnectServer.shared.activeSessions where subscribedSessions.contains(session.id) {
            try? session.send(envelope: env)
        }
    }
}
