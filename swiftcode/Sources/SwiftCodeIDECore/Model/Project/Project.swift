import Foundation

#if canImport(SwiftCodeCollaboration)
import SwiftCodeCollaboration
#endif

public struct Project: Identifiable, Codable, @unchecked Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var lastOpened: Date
    public var files: [FileNode]
    public var githubRepo: String?
    public var githubToken: String?
    public var description: String
    public var ciBuildConfiguration: CIBuildConfiguration?
#if canImport(SwiftCodeCollaboration)
    public var transferConfiguration: ProjectTransferConfiguration?
#endif
    public var customDirectoryPath: String?
    public var destinations: [String]?
    public var buildSettings: ProjectBuildSettings = ProjectBuildSettings()

    public enum CodingKeys: String, CodingKey {
        case id, name, createdAt, lastOpened, files, fileCount, githubRepo, description, ciBuildConfiguration
#if canImport(SwiftCodeCollaboration)
        case transferConfiguration
#endif
        case customDirectoryPath, destinations, buildSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastOpened = try container.decode(Date.self, forKey: .lastOpened)
        files = []
        fileCount = (try? container.decode(Int.self, forKey: .fileCount)) ?? 0
        githubRepo = try container.decodeIfPresent(String.self, forKey: .githubRepo)
        description = try container.decode(String.self, forKey: .description)
        ciBuildConfiguration = try container.decodeIfPresent(CIBuildConfiguration.self, forKey: .ciBuildConfiguration)
#if canImport(SwiftCodeCollaboration)
        transferConfiguration = try container.decodeIfPresent(ProjectTransferConfiguration.self, forKey: .transferConfiguration)
#endif
        customDirectoryPath = try container.decodeIfPresent(String.self, forKey: .customDirectoryPath)
        destinations = try container.decodeIfPresent([String].self, forKey: .destinations)
        buildSettings = try container.decodeIfPresent(ProjectBuildSettings.self, forKey: .buildSettings) ?? ProjectBuildSettings()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastOpened, forKey: .lastOpened)
        try container.encode([FileNode](), forKey: .files)
        try container.encode(fileCount, forKey: .fileCount)
        try container.encode(githubRepo, forKey: .githubRepo)
        try container.encode(description, forKey: .description)
        try container.encode(ciBuildConfiguration, forKey: .ciBuildConfiguration)
#if canImport(SwiftCodeCollaboration)
        try container.encode(transferConfiguration, forKey: .transferConfiguration)
#endif
        try container.encode(customDirectoryPath, forKey: .customDirectoryPath)
        try container.encodeIfPresent(destinations, forKey: .destinations)
        try container.encode(buildSettings, forKey: .buildSettings)
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
#if canImport(SwiftCodeCollaboration)
        self.transferConfiguration = .owner
#endif
        self.customDirectoryPath = nil
        self.destinations = ["iphonesimulator", "iphoneos", "macosx"]
    }

    @MainActor
    public var directoryURL: URL {
        if let customPath = customDirectoryPath {
            return URL(fileURLWithPath: customPath)
        }
        if name.hasPrefix("/") {
            return URL(fileURLWithPath: name)
        }
        return CodingManager.shared.projectsRoot.appendingPathComponent(name)
    }

    public var displayName: String {
        if let customPath = customDirectoryPath {
            return URL(fileURLWithPath: customPath).lastPathComponent
        }
        if name.hasPrefix("/") {
            return URL(fileURLWithPath: name).lastPathComponent
        }
        return name
    }

    public var fileCount: Int = 0
}

extension Project: Equatable {
    public static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.id == rhs.id
    }
}
