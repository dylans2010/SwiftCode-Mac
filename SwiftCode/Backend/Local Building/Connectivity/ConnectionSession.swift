import Foundation
import Network
import os.log

public enum ConnectionState: String, Codable, Sendable {
    case discovered
    case connecting
    case authenticating
    case connected
    case active
    case disconnected
}

@Observable
public final class ConnectionSession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let connection: NWConnection
    public var deviceID: String?
    public var deviceName: String?
    public var state: ConnectionState = .connecting
    public var sessionToken: String?
    public var grantedPermissions: Set<ConnectPermission> = []

    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "ConnectionSession")
    private var isFrameLoopRunning = false

    public init(id: UUID = UUID(), connection: NWConnection) {
        self.id = id
        self.connection = connection
    }

    public func start(onMessageReceived: @escaping @Sendable (MessageEnvelope, ConnectionSession) -> Void) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.logger.info("NWConnection ready for session \(self.id)")
                    self.state = .authenticating
                    self.receiveNextFrame(onMessageReceived: onMessageReceived)
                case .failed(let error):
                    self.logger.error("NWConnection failed for session \(self.id): \(error.localizedDescription)")
                    self.state = .disconnected
                case .cancelled:
                    self.state = .disconnected
                default:
                    break
                }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    public func send(envelope: MessageEnvelope) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(envelope)

        var length = UInt32(payloadData.count).bigEndian
        var packetData = Data(bytes: &length, count: 4)
        packetData.append(payloadData)

        connection.send(content: packetData, completion: .contentProcessed({ error in
            if let error = error {
                self.logger.error("Error sending packet on session \(self.id): \(error.localizedDescription)")
            }
        }))
    }

    public func disconnect() {
        state = .disconnected
        connection.cancel()
    }

    private func receiveNextFrame(onMessageReceived: @escaping @Sendable (MessageEnvelope, ConnectionSession) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, context, isComplete, error in
            guard let self = self, let data = data, data.count == 4, error == nil else {
                Task { @MainActor in self?.state = .disconnected }
                return
            }

            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { bodyData, bodyContext, bodyIsComplete, bodyError in
                guard let bodyData = bodyData, bodyData.count == Int(length), bodyError == nil else {
                    Task { @MainActor in self.state = .disconnected }
                    return
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let envelope = try? decoder.decode(MessageEnvelope.self, from: bodyData) {
                    onMessageReceived(envelope, self)
                }

                self.receiveNextFrame(onMessageReceived: onMessageReceived)
            }
        }
    }
}
