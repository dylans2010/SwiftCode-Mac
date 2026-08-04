import Foundation

public enum VMStatus: String, Codable, Sendable, CaseIterable {
    case stopped = "Stopped"
    case starting = "Starting"
    case running = "Running"
    case pausing = "Pausing"
    case paused = "Paused"
    case stopping = "Stopping"
    case error = "Error"

    public var icon: String {
        switch self {
        case .stopped: return "stop.fill"
        case .starting: return "play.circle.fill"
        case .running: return "play.fill"
        case .pausing: return "pause.circle.fill"
        case .paused: return "pause.fill"
        case .stopping: return "stop.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

public struct VMSharedFolder: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var hostPath: String
    public var guestMountPoint: String
    public var isReadOnly: Bool

    public init(id: UUID = UUID(), name: String, hostPath: String, guestMountPoint: String, isReadOnly: Bool = false) {
        self.id = id
        self.name = name
        self.hostPath = hostPath
        self.guestMountPoint = guestMountPoint
        self.isReadOnly = isReadOnly
    }
}

public struct VMPortForwarding: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var hostPort: Int
    public var guestPort: Int
    public var protocolType: String // "TCP" or "UDP"

    public init(id: UUID = UUID(), name: String, hostPort: Int, guestPort: Int, protocolType: String = "TCP") {
        self.id = id
        self.name = name
        self.hostPort = hostPort
        self.guestPort = guestPort
        self.protocolType = protocolType
    }
}

public struct VMSnapshot: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var description: String
    public var timestamp: Date

    public init(id: UUID = UUID(), name: String, description: String, timestamp: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.timestamp = timestamp
    }
}

public struct VirtualMachine: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var osType: String // Ubuntu, Debian, Fedora, Alpine
    public var version: String
    public var status: VMStatus
    public var cpuCores: Int
    public var memoryMB: Int
    public var storageGB: Int
    public var macAddress: String
    public var ipAddress: String
    public var uptime: TimeInterval
    public var createdDate: Date
    public var imagePath: String?
    public var sharedFolders: [VMSharedFolder]
    public var portForwardings: [VMPortForwarding]
    public var snapshots: [VMSnapshot]
    public var attachedProjects: [UUID] // Attached project IDs

    public init(
        id: UUID = UUID(),
        name: String,
        osType: String,
        version: String,
        status: VMStatus = .stopped,
        cpuCores: Int = 2,
        memoryMB: Int = 2048,
        storageGB: Int = 20,
        macAddress: String = "00:16:3E:\(String(format: "%02X:%02X:%02X", Int.random(in: 0...255), Int.random(in: 0...255), Int.random(in: 0...255)))",
        ipAddress: String = "192.168.64.\(Int.random(in: 2...254))",
        uptime: TimeInterval = 0,
        createdDate: Date = Date(),
        imagePath: String? = nil,
        sharedFolders: [VMSharedFolder] = [],
        portForwardings: [VMPortForwarding] = [],
        snapshots: [VMSnapshot] = [],
        attachedProjects: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.osType = osType
        self.version = version
        self.status = status
        self.cpuCores = cpuCores
        self.memoryMB = memoryMB
        self.storageGB = storageGB
        self.macAddress = macAddress
        self.ipAddress = ipAddress
        self.uptime = uptime
        self.createdDate = createdDate
        self.imagePath = imagePath
        self.sharedFolders = sharedFolders
        self.portForwardings = portForwardings
        self.snapshots = snapshots
        self.attachedProjects = attachedProjects
    }
}
