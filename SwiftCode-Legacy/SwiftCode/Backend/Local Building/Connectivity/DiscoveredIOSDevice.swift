import Foundation

/// Represents a SwiftCode iOS device discovered via Bonjour advertisement or resolved network endpoint.
public struct DiscoveredIOSDevice: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let host: String
    public let port: UInt16
    public let protocolVersion: String
    public let capabilities: [String]
    public let deviceType: String
    public var isAvailable: Bool
    public var lastSeen: Date
    public let txtRecord: [String: String]

    public init(
        id: String,
        name: String,
        host: String,
        port: UInt16,
        protocolVersion: String = "\(ConnectProtocolVersion.current)",
        capabilities: [String] = ConnectCapability.allCases.map { $0.rawValue },
        deviceType: String = ConnectDeviceType.iOS.rawValue,
        isAvailable: Bool = true,
        lastSeen: Date = Date(),
        txtRecord: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.deviceType = deviceType
        self.isAvailable = isAvailable
        self.lastSeen = lastSeen
        self.txtRecord = txtRecord
    }

    public var endpointDisplay: String {
        "\(host):\(port)"
    }
}
