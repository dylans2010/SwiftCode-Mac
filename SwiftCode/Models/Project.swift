import Foundation

public struct CIBuildConfiguration: Codable {
    public enum Platform: String, Codable, CaseIterable {
        case iOS
        case iOSAndIPadOS = "iOS + iPadOS"
    }

    public enum DeviceFamily: String, Codable, CaseIterable {
        case iPhone
        case iPad
        case iPhoneAndIPad = "iPhone + iPad"

        public var targetFamilyValue: String {
            switch self {
            case .iPhone: return "1"
            case .iPad: return "2"
            case .iPhoneAndIPad: return "1,2"
            }
        }
    }

    public var platform: Platform
    public var deploymentTarget: String
    public var targetDeviceFamily: DeviceFamily
    public var schemeName: String
    public var bundleIdentifier: String

    public init(
        platform: Platform = .iOS,
        deploymentTarget: String = "16.0",
        targetDeviceFamily: DeviceFamily = .iPhoneAndIPad,
        schemeName: String = "Test",
        bundleIdentifier: String = "com.example.myapp"
    ) {
        self.platform = platform
        self.deploymentTarget = deploymentTarget
        self.targetDeviceFamily = targetDeviceFamily
        self.schemeName = schemeName
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct Project: Identifiable, Codable, @unchecked Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var lastOpened: Date
    public var files: [FileNode]
    public var githubRepo: String?
    public var githubToken: String? // stored in keychain, not persisted here
    public var description: String
    public var ciBuildConfiguration: CIBuildConfiguration?
    public var transferConfiguration: ProjectTransferConfiguration?

    public enum CodingKeys: String, CodingKey {
        case id, name, createdAt, lastOpened, files, fileCount, githubRepo, description, ciBuildConfiguration, transferConfiguration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastOpened = try container.decode(Date.self, forKey: .lastOpened)
        files = try container.decode([FileNode].self, forKey: .files)
        fileCount = (try? container.decode(Int.self, forKey: .fileCount)) ?? 0
        githubRepo = try container.decodeIfPresent(String.self, forKey: .githubRepo)
        description = try container.decode(String.self, forKey: .description)
        ciBuildConfiguration = try container.decodeIfPresent(CIBuildConfiguration.self, forKey: .ciBuildConfiguration)
        transferConfiguration = try container.decodeIfPresent(ProjectTransferConfiguration.self, forKey: .transferConfiguration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastOpened, forKey: .lastOpened)
        try container.encode(files, forKey: .files)
        try container.encode(fileCount, forKey: .fileCount)
        try container.encode(githubRepo, forKey: .githubRepo)
        try container.encode(description, forKey: .description)
        try container.encode(ciBuildConfiguration, forKey: .ciBuildConfiguration)
        try container.encode(transferConfiguration, forKey: .transferConfiguration)
    }

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.lastOpened = Date()
        self.files = []
        self.fileCount = 0
        self.githubRepo = nil
        self.githubToken = nil
        self.description = ""
        self.ciBuildConfiguration = CIBuildConfiguration()
        self.transferConfiguration = .owner
    }

    @MainActor
    public var directoryURL: URL {
        CodingManager.shared.projectsRoot.appendingPathComponent(name)
    }

    public var fileCount: Int = 0
}


public struct ProjectTransferConfiguration: Codable, Hashable, Sendable {
    public var originPeerID: String?
    public var permission: TransferPermission
    public var lastTransferSessionID: UUID?
    public var lastTransferDate: Date?
    public var auditLog: [TransferAuditEntry]

    public init(originPeerID: String? = nil, permission: TransferPermission, lastTransferSessionID: UUID? = nil, lastTransferDate: Date? = nil, auditLog: [TransferAuditEntry] = []) {
        self.originPeerID = originPeerID
        self.permission = permission
        self.lastTransferSessionID = lastTransferSessionID
        self.lastTransferDate = lastTransferDate
        self.auditLog = auditLog
    }

    public static let owner = ProjectTransferConfiguration(permission: .owner)
}
