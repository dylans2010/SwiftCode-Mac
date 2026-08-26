import Foundation
import Network
import os.log

public enum ServerListenerState: Equatable, Sendable {
    case stopped
    case starting
    case listening(port: UInt16)
    case failed(String)
}

@Observable
@MainActor
public final class ConnectServer: @unchecked Sendable {
    public static let shared = ConnectServer()

    private static let portStorageKey = "com.swiftcode.connect.listening_port"

    public var configuredPort: UInt16 {
        didSet {
            UserDefaults.standard.set(Int(configuredPort), forKey: Self.portStorageKey)
        }
    }

    public private(set) var activePort: UInt16?
    public private(set) var activeSessions: [ConnectionSession] = []
    public private(set) var isRunning: Bool = false
    public private(set) var listenerState: ServerListenerState = .stopped
    public private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectServer")
    private var messageHandlers: [ConnectMessageType: @MainActor @Sendable (MessageEnvelope, ConnectionSession) async -> Void] = [:]

    private init() {
        let savedPort = UserDefaults.standard.integer(forKey: Self.portStorageKey)
        if savedPort >= Int(ConnectProtocol.validPortRange.lowerBound) && savedPort <= Int(ConnectProtocol.validPortRange.upperBound) {
            self.configuredPort = UInt16(savedPort)
        } else {
            self.configuredPort = ConnectProtocol.defaultPort
        }

        registerDefaultHandlers()
    }

    private func ensureServicesRegistered() {
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

    public func startServer(port: UInt16? = nil) async throws {
        let targetPort = port ?? configuredPort

        guard ConnectProtocol.validPortRange.contains(targetPort) else {
            let errorMsg = "Port \(targetPort) is outside the valid range (\(ConnectProtocol.validPortRange.lowerBound)-\(ConnectProtocol.validPortRange.upperBound))."
            self.lastError = errorMsg
            self.listenerState = .failed(errorMsg)
            throw ConnectErrorPayload(errorCode: .invalidPort, message: errorMsg)
        }

        ensureServicesRegistered()
        listenerState = .starting
        lastError = nil

        do {
            try await BonjourAdvertiser.shared.startAdvertising(port: targetPort) { [weak self] connection in
                Task { @MainActor in
                    self?.handleIncomingConnection(connection)
                }
            }

            self.activePort = targetPort
            self.configuredPort = targetPort
            self.isRunning = true
            self.listenerState = .listening(port: targetPort)
            self.logger.info("SwiftCode Connect Server successfully started and listening on port \(targetPort)")

            // Also start discovering nearby iOS devices
            IOSDiscoveryService.shared.startScanning()

        } catch let error as ConnectErrorPayload {
            self.isRunning = false
            self.activePort = nil
            self.listenerState = .failed(error.message)
            self.lastError = error.message
            self.logger.error("Failed to start SwiftCode Connect server on port \(targetPort): \(error.message)")
            throw error
        } catch {
            let errorMsg = "SwiftCode could not listen on port \(targetPort). The port may already be in use."
            self.isRunning = false
            self.activePort = nil
            self.listenerState = .failed(errorMsg)
            self.lastError = errorMsg
            self.logger.error("Failed to start SwiftCode Connect server: \(error.localizedDescription)")
            throw ConnectErrorPayload(errorCode: .portUnavailable, message: errorMsg, details: error.localizedDescription)
        }
    }

    public func applyPort(_ newPort: UInt16) async throws {
        guard ConnectProtocol.validPortRange.contains(newPort) else {
            let errorMsg = "Port \(newPort) is invalid. Must be between \(ConnectProtocol.validPortRange.lowerBound) and \(ConnectProtocol.validPortRange.upperBound)."
            self.lastError = errorMsg
            throw ConnectErrorPayload(errorCode: .invalidPort, message: errorMsg)
        }

        // If not running, just update the configured port
        guard isRunning else {
            self.configuredPort = newPort
            self.lastError = nil
            return
        }

        // Notify active sessions about the port update notice
        let notice = ConnectPortUpdateNoticePayload(deviceID: BonjourAdvertiser.shared.deviceID, newPort: newPort)
        if let envelope = try? MessageEnvelope.encode(payload: notice, type: .portUpdateNotice) {
            broadcast(envelope: envelope)
        }

        // Stop current listener and restart on the new port
        stopServer()
        try await startServer(port: newPort)
    }

    public func stopServer() {
        BonjourAdvertiser.shared.stopAdvertising()
        IOSDiscoveryService.shared.stopScanning()

        for session in activeSessions {
            session.disconnect()
        }
        activeSessions.removeAll()

        isRunning = false
        activePort = nil
        listenerState = .stopped
        logger.info("SwiftCode Connect Server stopped")
    }

    public func connectToDevice(host: String, port: UInt16) async throws -> ConnectionSession {
        guard ConnectProtocol.validPortRange.contains(port) else {
            throw ConnectErrorPayload(errorCode: .invalidPort, message: "Invalid remote port \(port)")
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ConnectErrorPayload(errorCode: .invalidPort, message: "Unable to parse port \(port)")
        }

        let nwHost = NWEndpoint.Host(host)
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let connection = NWConnection(host: nwHost, port: nwPort, using: parameters)
        let session = ConnectionSession(connection: connection, isInitiator: true)
        session.remoteHost = host
        session.remotePort = port

        activeSessions.append(session)

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            session.start { [weak self] envelope, activeSession in
                Task { @MainActor in
                    await self?.routeEnvelope(envelope, on: activeSession)
                }
            }

            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.logger.info("Outbound connection to \(host):\(port) established.")
                        session.state = .handshaking

                        // Initiate handshake
                        let handshake = ConnectHandshakePayload(
                            deviceID: BonjourAdvertiser.shared.deviceID,
                            deviceType: .macOS,
                            deviceName: BonjourAdvertiser.shared.macName,
                            protocolVersion: ConnectProtocolVersion.current,
                            appVersion: ConnectProtocol.currentAppVersion,
                            supportedCapabilities: ConnectCapability.allCases,
                            listeningPort: self.activePort
                        )

                        if let env = try? MessageEnvelope.encode(payload: handshake, type: .handshake) {
                            try? session.send(envelope: env)
                        }

                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(returning: session)
                        }

                    case .failed(let error):
                        self.logger.error("Outbound connection to \(host):\(port) failed: \(error.localizedDescription)")
                        session.state = .failed
                        self.activeSessions.removeAll(where: { $0.id == session.id })

                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(throwing: ConnectErrorPayload(
                                errorCode: .connectionRefused,
                                message: "The iOS device was reached, but no SwiftCode Connect listener accepted the connection.",
                                details: error.localizedDescription
                            ))
                        }

                    default:
                        break
                    }
                }
            }
        }
    }

    public func registerHandler(for type: ConnectMessageType, handler: @escaping @MainActor @Sendable (MessageEnvelope, ConnectionSession) async -> Void) {
        messageHandlers[type] = handler
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        let session = ConnectionSession(connection: connection, isInitiator: false)
        activeSessions.append(session)

        session.start { [weak self] envelope, currentSession in
            Task { @MainActor in
                await self?.routeEnvelope(envelope, on: currentSession)
            }
        }
    }

    public func routeEnvelope(_ envelope: MessageEnvelope, on session: ConnectionSession) async {
        // Clean up disconnected sessions
        if session.state == .disconnected || session.state == .failed {
            activeSessions.removeAll(where: { $0.id == session.id })
            return
        }

        guard envelope.protocolVersion == ConnectProtocolVersion.current else {
            logger.error("Protocol version mismatch: \(envelope.protocolVersion)")
            sendError(errorCode: .protocolMismatch, message: "Protocol version \(envelope.protocolVersion) not supported.", correlationID: envelope.messageID, on: session)
            return
        }

        // Allow initial handshake, pairing, auth, and ping prior to full session activation
        let unauthenticatedTypes: Set<ConnectMessageType> = [.handshake, .handshakeResponse, .pairingRequest, .pairingResponse, .authRequest, .authResponse, .ping, .pong, .disconnectNotice]

        if !unauthenticatedTypes.contains(envelope.type) {
            guard session.state == .active || session.state == .connected, let deviceID = session.deviceID else {
                sendError(errorCode: .unauthorized, message: "Session is not authenticated.", correlationID: envelope.messageID, on: session)
                return
            }
            TrustStore.shared.updateLastConnection(deviceID: deviceID)
        }

        if let handler = messageHandlers[envelope.type] {
            await handler(envelope, session)
        } else {
            logger.warning("No handler registered for type: \(envelope.type.rawValue)")
            sendError(errorCode: .notSupported, message: "Message type \(envelope.type.rawValue) is not supported.", correlationID: envelope.messageID, on: session)
        }
    }

    public func sendError(errorCode: ConnectErrorCode, message: String, details: String? = nil, correlationID: String?, on session: ConnectionSession) {
        let errorPayload = ConnectErrorPayload(errorCode: errorCode, message: message, details: details)
        if let envelope = try? MessageEnvelope.encode(payload: errorPayload, type: .errorResponse, correlationID: correlationID) {
            try? session.send(envelope: envelope)
        }
    }

    public func broadcast(envelope: MessageEnvelope, requiringPermission permission: ConnectPermission? = nil) {
        for session in activeSessions where session.state == .active || session.state == .connected {
            if let permission = permission {
                guard session.grantedPermissions.contains(permission) else { continue }
            }
            try? session.send(envelope: envelope)
        }
    }

    public func createAuthoritativeSyncPayload() -> ConnectSyncStatePayload {
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
                swiftVersion: ProjectRegistryManager.shared.registryEntries.first(where: { $0.id == p.id })?.swiftVersion ?? "6.0"
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
                swiftVersion: ProjectRegistryManager.shared.registryEntries.first(where: { $0.id == p.id })?.swiftVersion ?? "6.0"
            )
        }

        return ConnectSyncStatePayload(
            activeProject: activeProjectInfo,
            availableProjects: available,
            gitStatus: nil,
            currentBuildState: ConnectBuildService.shared.currentBuildState.rawValue,
            capabilities: ConnectCapability.allCases,
            permissions: ConnectPermission.allCases,
            serverTime: Date()
        )
    }

    private func registerDefaultHandlers() {
        // Ping & Pong
        registerHandler(for: .ping) { envelope, session in
            if let response = try? MessageEnvelope.encode(payload: ["pong": true], type: .pong, correlationID: envelope.messageID) {
                try? session.send(envelope: response)
            }
        }

        // Handshake Exchange
        registerHandler(for: .handshake) { [weak self] envelope, session in
            guard let self = self else { return }
            guard let payload = try? envelope.decodePayload(ConnectHandshakePayload.self) else {
                self.sendError(errorCode: .badRequest, message: "Invalid handshake payload.", correlationID: envelope.messageID, on: session)
                return
            }

            guard payload.deviceType == .iOS else {
                self.sendError(errorCode: .invalidDeviceType, message: "Remote device type must be iOS.", correlationID: envelope.messageID, on: session)
                return
            }

            session.deviceID = payload.deviceID
            session.deviceName = payload.deviceName
            session.deviceType = payload.deviceType
            session.protocolVersion = payload.protocolVersion
            if let port = payload.listeningPort {
                session.remotePort = port
            }
            session.state = .handshaking

            let response = ConnectHandshakeResponsePayload(
                accepted: true,
                deviceID: BonjourAdvertiser.shared.deviceID,
                deviceType: .macOS,
                deviceName: BonjourAdvertiser.shared.macName,
                protocolVersion: ConnectProtocolVersion.current,
                appVersion: ConnectProtocol.currentAppVersion,
                supportedCapabilities: ConnectCapability.allCases,
                listeningPort: self.activePort
            )

            if let respEnv = try? MessageEnvelope.encode(payload: response, type: .handshakeResponse, correlationID: envelope.messageID) {
                try? session.send(envelope: respEnv)
            }
        }

        // Pairing Request
        registerHandler(for: .pairingRequest) { [weak self] envelope, session in
            guard let self = self else { return }
            guard let payload = try? envelope.decodePayload(ConnectPairingRequestPayload.self) else {
                self.sendError(errorCode: .badRequest, message: "Invalid pairing payload.", correlationID: envelope.messageID, on: session)
                return
            }

            session.state = .pairing

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

                // Send authoritative state synchronization immediately upon pairing
                let syncPayload = self.createAuthoritativeSyncPayload()
                if let syncEnv = try? MessageEnvelope.encode(payload: syncPayload, type: .syncStateResponse) {
                    try? session.send(envelope: syncEnv)
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

        // Auth Request
        registerHandler(for: .authRequest) { [weak self] envelope, session in
            guard let self = self else { return }
            guard let payload = try? envelope.decodePayload(ConnectAuthRequestPayload.self) else {
                self.sendError(errorCode: .badRequest, message: "Invalid auth payload.", correlationID: envelope.messageID, on: session)
                return
            }

            session.state = .authenticating

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
                    serverVersion: ConnectProtocol.currentAppVersion,
                    capabilities: ConnectCapability.allCases,
                    permissions: device.permissions
                )

                if let respEnv = try? MessageEnvelope.encode(payload: response, type: .authResponse, correlationID: envelope.messageID) {
                    try? session.send(envelope: respEnv)
                }

                // Send authoritative state synchronization immediately upon authentication
                let syncPayload = self.createAuthoritativeSyncPayload()
                if let syncEnv = try? MessageEnvelope.encode(payload: syncPayload, type: .syncStateResponse) {
                    try? session.send(envelope: syncEnv)
                }

            } else {
                let response = ConnectAuthResponsePayload(
                    authenticated: false,
                    sessionID: nil,
                    serverVersion: ConnectProtocol.currentAppVersion,
                    capabilities: [],
                    permissions: []
                )
                if let respEnv = try? MessageEnvelope.encode(payload: response, type: .authResponse, correlationID: envelope.messageID) {
                    try? session.send(envelope: respEnv)
                }
                session.disconnect()
            }
        }

        // State Synchronization Request
        registerHandler(for: .syncStateRequest) { [weak self] envelope, session in
            guard let self = self else { return }
            let syncPayload = self.createAuthoritativeSyncPayload()
            if let respEnv = try? MessageEnvelope.encode(payload: syncPayload, type: .syncStateResponse, correlationID: envelope.messageID) {
                try? session.send(envelope: respEnv)
            }
        }

        // Disconnect Notice
        registerHandler(for: .disconnectNotice) { _, session in
            session.disconnect()
        }
    }
}
