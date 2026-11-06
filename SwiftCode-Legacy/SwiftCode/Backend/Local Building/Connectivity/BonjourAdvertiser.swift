import Foundation
import Network
import os.log

public enum AdvertiserState: Equatable, Sendable {
    case stopped
    case starting
    case advertising(port: UInt16)
    case failed(String)
}

@Observable
@MainActor
public final class BonjourAdvertiser: @unchecked Sendable {
    public static let shared = BonjourAdvertiser()

    public private(set) var isAdvertising: Bool = false
    public private(set) var advertisedPort: UInt16?
    public private(set) var state: AdvertiserState = .stopped
    public private(set) var macName: String = Host.current().localizedName ?? "SwiftCode Mac"
    public private(set) var deviceID: String = {
        let key = "com.swiftcode.connect.mac_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }()

    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "BonjourAdvertiser")
    private var listener: NWListener?
    private var connectionHandler: (@Sendable (NWConnection) -> Void)?

    private init() {}

    public func startAdvertising(
        port: UInt16 = ConnectProtocol.defaultPort,
        onConnectionHandler: (@Sendable (NWConnection) -> Void)? = nil
    ) async throws {
        if let onConnectionHandler = onConnectionHandler {
            self.connectionHandler = onConnectionHandler
        }

        // If already advertising on this exact port, no need to restart
        if isAdvertising && advertisedPort == port {
            return
        }

        // Stop existing listener before binding to new port
        stopAdvertising()

        guard ConnectProtocol.validPortRange.contains(port) else {
            let errorMsg = "Port \(port) is outside the valid range (\(ConnectProtocol.validPortRange.lowerBound)-\(ConnectProtocol.validPortRange.upperBound))."
            self.state = .failed(errorMsg)
            logger.error("\(errorMsg)")
            throw ConnectErrorPayload(errorCode: .invalidPort, message: errorMsg)
        }

        state = .starting
        let currentMacName = Host.current().localizedName ?? "SwiftCode Mac"
        self.macName = currentMacName

        let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port.any
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true

        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters, on: nwPort)
        } catch {
            let errorMsg = "SwiftCode could not listen on port \(port). The port may already be in use."
            self.state = .failed(errorMsg)
            logger.error("Failed to initialize NWListener on port \(port): \(error.localizedDescription)")
            throw ConnectErrorPayload(errorCode: .portUnavailable, message: errorMsg, details: error.localizedDescription)
        }

        let capsString = ConnectCapability.allCases.map { $0.rawValue }.joined(separator: ",")
        let txtRecord = NWTXTRecord([
            "txtvers": "1",
            "proto": "\(ConnectProtocolVersion.current)",
            "deviceName": currentMacName,
            "deviceID": deviceID,
            "deviceType": ConnectDeviceType.macOS.rawValue,
            "port": "\(port)",
            "caps": capsString,
            "appVers": ConnectProtocol.currentAppVersion
        ])

        newListener.service = NWListener.Service(
            name: currentMacName,
            type: ConnectProtocol.serviceType,
            domain: nil,
            txtRecord: txtRecord
        )

        self.listener = newListener

        // Await socket binding state confirmation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class ResumeState: @unchecked Sendable {
                var hasResumed = false
                let continuation: CheckedContinuation<Void, Error>
                init(continuation: CheckedContinuation<Void, Error>) {
                    self.continuation = continuation
                }
                func resume() {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume()
                }
                func resume(throwing error: Error) {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(throwing: error)
                }
            }

            let resumeState = ResumeState(continuation: continuation)

            newListener.stateUpdateHandler = { [weak self] listenerState in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch listenerState {
                    case .ready:
                        let boundPort = newListener.port?.rawValue ?? port
                        self.advertisedPort = boundPort
                        self.isAdvertising = true
                        self.state = .advertising(port: boundPort)
                        self.logger.info("SwiftCode Connect Bonjour advertiser successfully ready on port \(boundPort)")
                        resumeState.resume()

                    case .failed(let error):
                        let errorMsg = "SwiftCode could not listen on port \(port). The port may already be in use."
                        self.logger.error("NWListener failed on port \(port): \(error.localizedDescription)")
                        self.stopAdvertising()
                        self.state = .failed(errorMsg)
                        resumeState.resume(throwing: ConnectErrorPayload(
                            errorCode: .portUnavailable,
                            message: errorMsg,
                            details: error.localizedDescription
                        ))

                    case .cancelled:
                        self.isAdvertising = false
                        self.advertisedPort = nil
                        self.state = .stopped
                        self.logger.info("NWListener cancelled on port \(port)")

                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.connectionHandler?(connection)
                }
            }

            newListener.start(queue: .global(qos: .userInitiated))
        }
    }

    public func stopAdvertising() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        isAdvertising = false
        advertisedPort = nil
        state = .stopped
        logger.info("SwiftCode Connect Bonjour advertiser stopped")
    }

    public func updateAdvertisedMetadata() {
        guard let listener = listener, isAdvertising, let port = advertisedPort else { return }

        let currentMacName = Host.current().localizedName ?? "SwiftCode Mac"
        self.macName = currentMacName

        let capsString = ConnectCapability.allCases.map { $0.rawValue }.joined(separator: ",")
        let txtRecord = NWTXTRecord([
            "txtvers": "1",
            "proto": "\(ConnectProtocolVersion.current)",
            "deviceName": currentMacName,
            "deviceID": deviceID,
            "deviceType": ConnectDeviceType.macOS.rawValue,
            "port": "\(port)",
            "caps": capsString,
            "appVers": ConnectProtocol.currentAppVersion
        ])

        listener.service = NWListener.Service(
            name: currentMacName,
            type: ConnectProtocol.serviceType,
            domain: nil,
            txtRecord: txtRecord
        )
        logger.info("Updated Bonjour TXT metadata for port \(port)")
    }
}
