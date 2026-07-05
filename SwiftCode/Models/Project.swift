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

public struct Project: Identifiable, Codable {
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

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.lastOpened = Date()
        self.files = []
        self.githubRepo = nil
        self.githubToken = nil
        self.description = ""
        self.ciBuildConfiguration = CIBuildConfiguration()
        self.transferConfiguration = .owner
    }

    @MainActor
    public var directoryURL: URL {
        ProjectManager.shared.projectsDirectory.appendingPathComponent(name)
    }

    public var fileCount: Int {
        countFiles(in: files)
    }

    private func countFiles(in nodes: [FileNode]) -> Int {
        nodes.reduce(0) { count, node in
            if node.isDirectory {
                return count + countFiles(in: node.children)
            } else {
                return count + 1
            }
        }
    }
}


public struct ProjectTransferConfiguration: Codable, Hashable {
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
