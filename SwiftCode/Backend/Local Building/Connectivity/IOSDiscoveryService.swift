import Foundation
import Network
import Observation
import os.log

@Observable
@MainActor
public final class IOSDiscoveryService: NSObject, @unchecked Sendable {
    public static let shared = IOSDiscoveryService()

    public private(set) var discoveredDevices: [DiscoveredIOSDevice] = []
    public private(set) var isScanning: Bool = false

    private let logger = Logger(subsystem: "com.swiftcode.connect", category: "IOSDiscoveryService")
    private var browser: NWBrowser?

    public override init() {
        super.init()
    }

    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: ConnectProtocol.serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.logger.info("Bonjour browser ready for service \(ConnectProtocol.serviceType)")
                case .failed(let error):
                    self.logger.error("Bonjour browser failed: \(error.localizedDescription)")
                    self.isScanning = false
                case .cancelled:
                    self.isScanning = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results: results, changes: changes)
            }
        }

        browser.start(queue: .global(qos: .userInitiated))
        logger.info("Started browsing for SwiftCode Connect iOS endpoints")
    }

    public func stopScanning() {
        browser?.cancel()
        browser = nil
        isScanning = false
        logger.info("Stopped browsing for SwiftCode Connect iOS endpoints")
    }

    public func refresh() {
        stopScanning()
        discoveredDevices.removeAll()
        startScanning()
    }

    private func handleBrowseResults(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        var devices: [DiscoveredIOSDevice] = []

        for result in results {
            var txtDict: [String: String] = [:]
            if case let .bonjour(txtRecord) = result.metadata {
                txtDict = txtRecord.dictionary
            }

            var serviceName = "iOS Device"
            var host = "unknown.local"
            var port: UInt16 = ConnectProtocol.defaultPort

            switch result.endpoint {
            case .service(let name, _, _, _):
                serviceName = name
                host = "\(name.replacingOccurrences(of: " ", with: "-")).local"
            case .hostPort(let nwHost, let nwPort):
                host = "\(nwHost)"
                port = nwPort.rawValue
            default:
                break
            }

            // Prefer port from TXT record if advertised explicitly
            if let portStr = txtDict["port"], let parsedPort = UInt16(portStr) {
                port = parsedPort
            }

            let deviceID = txtDict["deviceID"] ?? "\(serviceName)_\(host)_\(port)"
            let deviceName = txtDict["deviceName"] ?? serviceName
            let deviceType = txtDict["deviceType"] ?? ConnectDeviceType.iOS.rawValue
            let proto = txtDict["proto"] ?? "\(ConnectProtocolVersion.current)"
            let capsString = txtDict["caps"] ?? ""
            let capabilities = capsString.isEmpty ? ConnectCapability.allCases.map { $0.rawValue } : capsString.components(separatedBy: ",")

            let discovered = DiscoveredIOSDevice(
                id: deviceID,
                name: deviceName,
                host: host,
                port: port,
                protocolVersion: proto,
                capabilities: capabilities,
                deviceType: deviceType,
                isAvailable: true,
                lastSeen: Date(),
                txtRecord: txtDict
            )

            devices.append(discovered)
        }

        self.discoveredDevices = devices
        logger.debug("Discovered \(devices.count) SwiftCode Connect endpoints on local network")
    }
}
