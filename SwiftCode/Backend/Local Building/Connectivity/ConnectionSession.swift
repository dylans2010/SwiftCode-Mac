import Foundation
import Network
import os.log

public enum ConnectionState: String, Codable, Sendable {
    case idle
    case discovering
    case deviceDiscovered
    case connecting
    case transportConnected
    case handshaking
    case authenticating
    case pairing
    case synchronizing
    case connected
    case active
    case disconnected
    case failed
}

@Observable
public final class ConnectionSession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let connection: NWConnection
    public let isInitiator: Bool

    public var deviceID: String?
    public var deviceName: String?
    public var deviceType: ConnectDeviceType?
    public var state: ConnectionState = .connecting
    public var sessionToken: String?
    public var grantedPermissions: Set<ConnectPermission> = []

    public var localHost: String?
    public var localPort: UInt16?
    public var remoteHost: String?
    public var remotePort: UInt16?
    public var transportType: String = "TCP"
    public var protocolVersion: Int = ConnectProtocolVersion.current

    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectionSession")
    private var isFrameLoopRunning = false

    public init(id: UUID = UUID(), connection: NWConnection, isInitiator: Bool = false) {
        self.id = id
        self.connection = connection
        self.isInitiator = isInitiator

        extractEndpoints()
    }

    private func extractEndpoints() {
        if case let .hostPort(host, port) = connection.endpoint {
            self.remoteHost = "\(host)"
            self.remotePort = port.rawValue
        }
    }

    public func start(onMessageReceived: @escaping @Sendable (MessageEnvelope, ConnectionSession) -> Void) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.logger.info("NWConnection ready for session \(self.id)")
                    self.extractLocalEndpoint()
                    self.state = .transportConnected
                    self.receiveNextFrame(onMessageReceived: onMessageReceived)

                case .failed(let error):
                    self.logger.error("NWConnection failed for session \(self.id): \(error.localizedDescription)")
                    self.state = .failed

                case .cancelled:
                    self.logger.info("NWConnection cancelled for session \(self.id)")
                    self.state = .disconnected

                case .waiting(let error):
                    self.logger.warning("NWConnection waiting for session \(self.id): \(error.localizedDescription)")

                default:
                    break
                }
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    private func extractLocalEndpoint() {
        if let currentPath = connection.currentPath,
           let localEndpoint = currentPath.localEndpoint,
           case let .hostPort(host, port) = localEndpoint {
            self.localHost = "\(host)"
            self.localPort = port.rawValue
        }

        if let currentPath = connection.currentPath,
           let remoteEndpoint = currentPath.remoteEndpoint,
           case let .hostPort(host, port) = remoteEndpoint {
            self.remoteHost = "\(host)"
            self.remotePort = port.rawValue
        }
    }

    public func send(envelope: MessageEnvelope) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(envelope)

        var length = UInt32(payloadData.count).bigEndian
        var packetData = Data(bytes: &length, count: 4)
        packetData.append(payloadData)

        connection.send(content: packetData, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                self?.logger.error("Error sending packet on session \(self?.id.uuidString ?? ""): \(error.localizedDescription)")
            }
        }))
    }

    public func disconnect() {
        state = .disconnected
        connection.cancel()
    }

    private func receiveNextFrame(onMessageReceived: @escaping @Sendable (MessageEnvelope, ConnectionSession) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 4, error == nil else {
                Task { @MainActor in
                    self?.state = .disconnected
                }
                return
            }

            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            // Guard against unbounded packet frames
            guard length > 0 && length < 10_000_000 else {
                self.logger.error("Invalid packet frame length received: \(length)")
                Task { @MainActor in
                    self.state = .failed
                }
                self.disconnect()
                return
            }

            self.connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { bodyData, _, _, bodyError in
                guard let bodyData = bodyData, bodyData.count == Int(length), bodyError == nil else {
                    Task { @MainActor in
                        self.state = .disconnected
                    }
                    return
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let envelope = try? decoder.decode(MessageEnvelope.self, from: bodyData) {
                    onMessageReceived(envelope, self)
                } else {
                    self.logger.error("Failed to decode message envelope for session \(self.id)")
                }

                self.receiveNextFrame(onMessageReceived: onMessageReceived)
            }
        }
    }
}
