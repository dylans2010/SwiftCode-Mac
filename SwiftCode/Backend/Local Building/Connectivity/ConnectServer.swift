import Foundation
import Network
import os.log

@Observable
@MainActor
public final class ConnectServer: @unchecked Sendable {
    public static let shared = ConnectServer()

    public private(set) var activeSessions: [ConnectionSession] = []
    public private(set) var isRunning: Bool = false

    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectServer")
    private var messageHandlers: [ConnectMessageType: @MainActor @Sendable (MessageEnvelope, ConnectionSession) async -> Void] = [:]

    private init() {
        registerDefaultHandlers()
        registerAllServices()
    }

    private func registerAllServices() {
        ConnectProjectService.shared.registerHandlers()
        ConnectGitService.shared.registerHandlers()
        ConnectBuildService.shared.registerHandlers()
        ConnectTestService.shared.registerHandlers()
        ConnectLogService.shared.registerHandlers()
        ConnectTerminalService.shared.registerHandlers()
        ConnectFileService.shared.registerHandlers()
        ConnectAssistService.shared.registerHandlers()
        ConnectDeviceService.shared.registerHandlers()
    }

    public func startServer(port: UInt16 = 8088) {
        guard !isRunning else { return }
        isRunning = true

        BonjourAdvertiser.shared.startAdvertising(port: port) { [weak self] connection in
            Task { @MainActor in
                self?.handleIncomingConnection(connection)
            }
        }
        logger.info("SwiftCode Connect Server started on port \(port)")
    }

    public func stopServer() {
        BonjourAdvertiser.shared.stopAdvertising()
        for session in activeSessions {
            session.disconnect()
        }
        activeSessions.removeAll()
        isRunning = false
        logger.info("SwiftCode Connect Server stopped")
    }

    public func registerHandler(for type: ConnectMessageType, handler: @escaping @MainActor @Sendable (MessageEnvelope, ConnectionSession) async -> Void) {
        messageHandlers[type] = handler
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        let session = ConnectionSession(connection: connection)
        activeSessions.append(session)

        session.start { [weak self] envelope, session in
            Task { @MainActor in
                await self?.routeEnvelope(envelope, on: session)
            }
        }
    }

    public func routeEnvelope(_ envelope: MessageEnvelope, on session: ConnectionSession) async {
        guard envelope.protocolVersion == ConnectProtocolVersion.current else {
            logger.error("Protocol version mismatch: \(envelope.protocolVersion)")
            sendError(code: "PROTOCOL_MISMATCH", message: "Protocol version \(envelope.protocolVersion) not supported.", correlationID: envelope.messageID, on: session)
            return
        }

        // Allow pairing and auth requests prior to full session activation
        if envelope.type != .pairingRequest && envelope.type != .authRequest && envelope.type != .ping {
            guard session.state == .active, let deviceID = session.deviceID else {
                sendError(code: "UNAUTHORIZED", message: "Session is not authenticated.", correlationID: envelope.messageID, on: session)
                return
            }
            TrustStore.shared.updateLastConnection(deviceID: deviceID)
        }

        if let handler = messageHandlers[envelope.type] {
            await handler(envelope, session)
        } else {
            logger.warning("No handler registered for type: \(envelope.type.rawValue)")
            sendError(code: "NOT_SUPPORTED", message: "Message type \(envelope.type.rawValue) is not supported.", correlationID: envelope.messageID, on: session)
        }
    }

    public func sendError(code: String, message: String, details: String? = nil, correlationID: String?, on session: ConnectionSession) {
        let errorPayload = ConnectErrorPayload(code: code, message: message, details: details)
        if let envelope = try? MessageEnvelope.encode(payload: errorPayload, type: .errorResponse, correlationID: correlationID) {
            try? session.send(envelope: envelope)
        }
    }

    public func broadcast(envelope: MessageEnvelope, requiringPermission permission: ConnectPermission? = nil) {
        for session in activeSessions where session.state == .active {
            if let permission = permission {
                guard session.grantedPermissions.contains(permission) else { continue }
            }
            try? session.send(envelope: envelope)
        }
    }

    private func registerDefaultHandlers() {
        // Handshake & Authentication Handlers
        registerHandler(for: .ping) { envelope, session in
            if let response = try? MessageEnvelope.encode(payload: ["pong": true], type: .pong, correlationID: envelope.messageID) {
                try? session.send(envelope: response)
            }
        }

        registerHandler(for: .pairingRequest) { [weak self] envelope, session in
            guard let payload = try? envelope.decodePayload(ConnectPairingRequestPayload.self) else {
                self?.sendError(code: "BAD_REQUEST", message: "Invalid pairing payload.", correlationID: envelope.messageID, on: session)
                return
            }

            let pending = PendingPairingRequest(
                deviceID: payload.deviceID,
                deviceName: payload.deviceName,
                deviceModel: payload.deviceModel,
                clientVersion: payload.clientVersion,
                verificationCode: payload.verificationCode
            )

            let approved = await PairingManager.shared.requestPairing(pending)
            if approved, let device = TrustStore.shared.getDevice(deviceID: payload.deviceID) {
                session.deviceID = device.id
                session.deviceName = device.name
                session.sessionToken = device.sessionToken
                session.grantedPermissions = Set(device.permissions)
                session.state = .active

                let responsePayload = ConnectPairingResponsePayload(
                    approved: true,
                    macName: BonjourAdvertiser.shared.macName,
                    sessionToken: device.sessionToken,
                    verificationCode: payload.verificationCode,
                    capabilities: ConnectCapability.allCases,
                    grantedPermissions: device.permissions
                )

                if let respEnv = try? MessageEnvelope.encode(payload: responsePayload, type: .pairingResponse, correlationID: envelope.messageID) {
                    try? session.send(envelope: respEnv)
                }
            } else {
                let responsePayload = ConnectPairingResponsePayload(
                    approved: false,
                    macName: BonjourAdvertiser.shared.macName,
                    sessionToken: nil,
                    verificationCode: nil,
                    capabilities: [],
                    grantedPermissions: []
                )
                if let respEnv = try? MessageEnvelope.encode(payload: responsePayload, type: .pairingResponse, correlationID: envelope.messageID) {
                    try? session.send(envelope: respEnv)
                }
                session.disconnect()
            }
        }

        registerHandler(for: .authRequest) { [weak self] envelope, session in
            guard let payload = try? envelope.decodePayload(ConnectAuthRequestPayload.self) else {
                self?.sendError(code: "BAD_REQUEST", message: "Invalid auth payload.", correlationID: envelope.messageID, on: session)
                return
            }

            if let device = TrustStore.shared.getDevice(deviceID: payload.deviceID),
               !device.isRevoked,
               device.sessionToken == payload.sessionToken {
                session.deviceID = device.id
                session.deviceName = device.name
                session.sessionToken = device.sessionToken
                session.grantedPermissions = Set(device.permissions)
                session.state = .active

                TrustStore.shared.updateLastConnection(deviceID: device.id)

                let response = ConnectAuthResponsePayload(
                    authenticated: true,
                    sessionID: session.id.uuidString,
                    serverVersion: "1.0",
                    capabilities: ConnectCapability.allCases,
                    permissions: device.permissions
                )

                if let respEnv = try? MessageEnvelope.encode(payload: response, type: .authResponse, correlationID: envelope.messageID) {
                    try? session.send(envelope: respEnv)
                }
            } else {
                let response = ConnectAuthResponsePayload(
                    authenticated: false,
                    sessionID: nil,
                    serverVersion: "1.0",
                    capabilities: [],
                    permissions: []
                )
                if let respEnv = try? MessageEnvelope.encode(payload: response, type: .authResponse, correlationID: envelope.messageID) {
                    try? session.send(envelope: respEnv)
                }
                session.disconnect()
            }
        }
    }
}
