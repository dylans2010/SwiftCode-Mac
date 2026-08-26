import Foundation
import Network
import Observation

public struct SessionDiagnosticInfo: Identifiable, Sendable {
    public let id: UUID
    public let deviceName: String
    public let deviceID: String
    public let deviceType: String
    public let remoteHost: String
    public let remotePort: UInt16
    public let localHost: String
    public let localPort: UInt16
    public let transport: String
    public let authStatus: String
    public let protocolVersion: String
    public let sessionState: String
    public let permissions: [String]

    public init(
        id: UUID,
        deviceName: String,
        deviceID: String,
        deviceType: String,
        remoteHost: String,
        remotePort: UInt16,
        localHost: String,
        localPort: UInt16,
        transport: String = "TCP",
        authStatus: String,
        protocolVersion: String = "v\(ConnectProtocolVersion.current)",
        sessionState: String,
        permissions: [String]
    ) {
        self.id = id
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.deviceType = deviceType
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.localHost = localHost
        self.localPort = localPort
        self.transport = transport
        self.authStatus = authStatus
        self.protocolVersion = protocolVersion
        self.sessionState = sessionState
        self.permissions = permissions
    }
}

@Observable
@MainActor
public final class ConnectDiagnostics: @unchecked Sendable {
    public static let shared = ConnectDiagnostics()

    public private(set) var localIPAddress: String = "127.0.0.1"

    private init() {
        refreshLocalIP()
    }

    public func refreshLocalIP() {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" || name == "bridge0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(
                            interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        )
                        let ip = String(cString: hostname)
                        if !ip.isEmpty && ip != "127.0.0.1" {
                            address = ip
                            break
                        }
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        self.localIPAddress = address
    }

    public func getDiagnostics(
        server: ConnectServer,
        bonjour: BonjourAdvertiser,
        discovery: IOSDiscoveryService
    ) -> [SessionDiagnosticInfo] {
        server.activeSessions.map { session in
            let authStatus: String
            switch session.state {
            case .active, .connected:
                authStatus = "Authenticated"
            case .authenticating, .pairing, .handshaking:
                authStatus = "Authenticating"
            default:
                authStatus = "Unauthenticated"
            }

            return SessionDiagnosticInfo(
                id: session.id,
                deviceName: session.deviceName ?? "Unknown Device",
                deviceID: session.deviceID ?? "N/A",
                deviceType: session.deviceType?.rawValue ?? "iOS",
                remoteHost: session.remoteHost ?? "0.0.0.0",
                remotePort: session.remotePort ?? 0,
                localHost: session.localHost ?? localIPAddress,
                localPort: session.localPort ?? bonjour.advertisedPort ?? server.configuredPort,
                transport: session.transportType,
                authStatus: authStatus,
                protocolVersion: "v\(session.protocolVersion)",
                sessionState: session.state.rawValue.capitalized,
                permissions: session.grantedPermissions.map { $0.rawValue }
            )
        }
    }
}
