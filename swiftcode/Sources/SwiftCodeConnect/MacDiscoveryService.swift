import Foundation
import Network
import Observation
import os.log

public struct DiscoveredMac: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let host: String
    public let port: Int

    public init(id: UUID = UUID(), name: String, host: String, port: Int) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }
}

@Observable
@MainActor
public final class MacDiscoveryService: NSObject, @unchecked Sendable {
    public var discoveredMacs: [DiscoveredMac] = []
    public var isScanning = false

    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "MacDiscoveryService")
    private var browser: NWBrowser?

    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        discoveredMacs = []

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: ConnectProtocol.serviceType, domain: nil), using: parameters)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }

            Task { @MainActor in
                self.discoveredMacs = results.compactMap { result in
                    var txtDict: [String: String] = [:]
                    if case let .bonjour(txtRecord) = result.metadata {
                        txtDict = txtRecord.dictionary
                    }

                    let port = Int(txtDict["port"] ?? "") ?? Int(ConnectProtocol.defaultPort)

                    if case let .service(name, _, _, _) = result.endpoint {
                        return DiscoveredMac(
                            name: txtDict["deviceName"] ?? name,
                            host: "\(name.replacingOccurrences(of: " ", with: "-")).local",
                            port: port
                        )
                    } else if case let .hostPort(host, nwPort) = result.endpoint {
                        return DiscoveredMac(
                            name: txtDict["deviceName"] ?? "\(host)",
                            host: "\(host)",
                            port: Int(nwPort.rawValue)
                        )
                    }
                    return nil
                }
            }
        }

        browser.start(queue: .global(qos: .userInitiated))
        logger.info("MacDiscoveryService started scanning for \(ConnectProtocol.serviceType)")
    }

    public func stopScanning() {
        browser?.cancel()
        browser = nil
        isScanning = false
        logger.info("MacDiscoveryService stopped scanning")
    }
}
