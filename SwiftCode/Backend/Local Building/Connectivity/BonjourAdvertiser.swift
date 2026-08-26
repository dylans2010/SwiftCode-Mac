import Foundation
import Network
import os.log

@Observable
@MainActor
public final class BonjourAdvertiser: @unchecked Sendable {
    public static let shared = BonjourAdvertiser()

    public private(set) var isAdvertising: Bool = false
    public private(set) var advertisedPort: UInt16?
    public private(set) var macName: String = Host.current().localizedName ?? "Mac"

    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "BonjourAdvertiser")
    private var listener: NWListener?

    private init() {}

    public func startAdvertising(port: UInt16 = 8088, onConnectionHandler: (@Sendable (NWConnection) -> Void)? = nil) {
        guard !isAdvertising else { return }

        do {
            let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port.any
            let parameters = NWParameters.tcp

            let listener = try NWListener(using: parameters, on: nwPort)

            // Configure Bonjour Service Discovery Metadata
            let macName = Host.current().localizedName ?? "SwiftCode Mac"
            self.macName = macName

            let txtRecord = NWTXTRecord([
                "txtvers": "1",
                "proto": "\(ConnectProtocolVersion.current)",
                "macName": macName,
                "appVers": "1.0"
            ])

            listener.service = NWListener.Service(
                name: macName,
                type: "_swiftcodeconnect._tcp",
                domain: nil,
                txtRecord: txtRecord
            )

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        if let assignedPort = listener.port?.rawValue {
                            self?.advertisedPort = assignedPort
                            self?.isAdvertising = true
                            self?.logger.info("Bonjour service successfully advertising on port \(assignedPort)")
                        }
                    case .failed(let error):
                        self?.logger.error("Bonjour listener failed: \(error.localizedDescription)")
                        self?.stopAdvertising()
                    case .cancelled:
                        self?.isAdvertising = false
                        self?.advertisedPort = nil
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { connection in
                onConnectionHandler?(connection)
            }

            self.listener = listener
            listener.start(queue: .global(qos: .userInitiated))

        } catch {
            logger.error("Failed to initialize NWListener: \(error.localizedDescription)")
        }
    }

    public func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
        advertisedPort = nil
        logger.info("Bonjour service stopped advertising")
    }
}
