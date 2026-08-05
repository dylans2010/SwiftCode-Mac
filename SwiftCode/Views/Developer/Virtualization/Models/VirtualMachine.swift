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
    public var notes: String?
    public var tags: [String]?

    public init(id: UUID = UUID(), name: String, description: String, timestamp: Date = Date(), notes: String? = nil, tags: [String]? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.timestamp = timestamp
        self.notes = notes
        self.tags = tags
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

    // Expanded SCVirtualizationKit Subsystems
    public var isPinned: Bool
    public var isFavorite: Bool
    public var isBookmarked: Bool
    public var labels: [String]
    public var startupActions: [String]
    public var shutdownActions: [String]
    public var bootCount: Int
    public var avgBootTime: Double
    public var avgShutdownTime: Double
    public var resourceUsageHistory: [Double]
    public var packageCount: Int
    public var projectCount: Int
    public var isFirstRun: Bool
    public var installedPackagesList: [String]
    public var activeTerminalCount: Int

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
        attachedProjects: [UUID] = [],
        isPinned: Bool = false,
        isFavorite: Bool = false,
        isBookmarked: Bool = false,
        labels: [String] = [],
        startupActions: [String] = [],
        shutdownActions: [String] = [],
        bootCount: Int = 0,
        avgBootTime: Double = 0.0,
        avgShutdownTime: Double = 0.0,
        resourceUsageHistory: [Double] = [],
        packageCount: Int = 0,
        projectCount: Int = 0,
        isFirstRun: Bool = true,
        installedPackagesList: [String] = [],
        activeTerminalCount: Int = 1
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
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.isBookmarked = isBookmarked
        self.labels = labels
        self.startupActions = startupActions
        self.shutdownActions = shutdownActions
        self.bootCount = bootCount
        self.avgBootTime = avgBootTime
        self.avgShutdownTime = avgShutdownTime
        self.resourceUsageHistory = resourceUsageHistory
        self.packageCount = packageCount
        self.projectCount = projectCount
        self.isFirstRun = isFirstRun
        self.installedPackagesList = installedPackagesList
        self.activeTerminalCount = activeTerminalCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, osType, version, status, cpuCores, memoryMB, storageGB
        case macAddress, ipAddress, uptime, createdDate, imagePath
        case sharedFolders, portForwardings, snapshots, attachedProjects
        case isPinned, isFavorite, isBookmarked, labels, startupActions, shutdownActions
        case bootCount, avgBootTime, avgShutdownTime, resourceUsageHistory, packageCount
        case projectCount, isFirstRun, installedPackagesList, activeTerminalCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        osType = try container.decode(String.self, forKey: .osType)
        version = try container.decode(String.self, forKey: .version)
        status = try container.decode(VMStatus.self, forKey: .status)
        cpuCores = try container.decode(Int.self, forKey: .cpuCores)
        memoryMB = try container.decode(Int.self, forKey: .memoryMB)
        storageGB = try container.decode(Int.self, forKey: .storageGB)
        macAddress = try container.decode(String.self, forKey: .macAddress)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        uptime = try container.decode(TimeInterval.self, forKey: .uptime)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        sharedFolders = try container.decodeIfPresent([VMSharedFolder].self, forKey: .sharedFolders) ?? []
        portForwardings = try container.decodeIfPresent([VMPortForwarding].self, forKey: .portForwardings) ?? []
        snapshots = try container.decodeIfPresent([VMSnapshot].self, forKey: .snapshots) ?? []
        attachedProjects = try container.decodeIfPresent([UUID].self, forKey: .attachedProjects) ?? []

        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        startupActions = try container.decodeIfPresent([String].self, forKey: .startupActions) ?? []
        shutdownActions = try container.decodeIfPresent([String].self, forKey: .shutdownActions) ?? []
        bootCount = try container.decodeIfPresent(Int.self, forKey: .bootCount) ?? 0
        avgBootTime = try container.decodeIfPresent(Double.self, forKey: .avgBootTime) ?? 0.0
        avgShutdownTime = try container.decodeIfPresent(Double.self, forKey: .avgShutdownTime) ?? 0.0
        resourceUsageHistory = try container.decodeIfPresent([Double].self, forKey: .resourceUsageHistory) ?? []
        packageCount = try container.decodeIfPresent(Int.self, forKey: .packageCount) ?? 0
        projectCount = try container.decodeIfPresent(Int.self, forKey: .projectCount) ?? 0
        isFirstRun = try container.decodeIfPresent(Bool.self, forKey: .isFirstRun) ?? true
        installedPackagesList = try container.decodeIfPresent([String].self, forKey: .installedPackagesList) ?? []
        activeTerminalCount = try container.decodeIfPresent(Int.self, forKey: .activeTerminalCount) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(osType, forKey: .osType)
        try container.encode(version, forKey: .version)
        try container.encode(status, forKey: .status)
        try container.encode(cpuCores, forKey: .cpuCores)
        try container.encode(memoryMB, forKey: .memoryMB)
        try container.encode(storageGB, forKey: .storageGB)
        try container.encode(macAddress, forKey: .macAddress)
        try container.encode(ipAddress, forKey: .ipAddress)
        try container.encode(uptime, forKey: .uptime)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(sharedFolders, forKey: .sharedFolders)
        try container.encode(portForwardings, forKey: .portForwardings)
        try container.encode(snapshots, forKey: .snapshots)
        try container.encode(attachedProjects, forKey: .attachedProjects)

        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(isBookmarked, forKey: .isBookmarked)
        try container.encode(labels, forKey: .labels)
        try container.encode(startupActions, forKey: .startupActions)
        try container.encode(shutdownActions, forKey: .shutdownActions)
        try container.encode(bootCount, forKey: .bootCount)
        try container.encode(avgBootTime, forKey: .avgBootTime)
        try container.encode(avgShutdownTime, forKey: .avgShutdownTime)
        try container.encode(resourceUsageHistory, forKey: .resourceUsageHistory)
        try container.encode(packageCount, forKey: .packageCount)
        try container.encode(projectCount, forKey: .projectCount)
        try container.encode(isFirstRun, forKey: .isFirstRun)
        try container.encode(installedPackagesList, forKey: .installedPackagesList)
        try container.encode(activeTerminalCount, forKey: .activeTerminalCount)
    }
}
