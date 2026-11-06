import Foundation

/// The `.scproj` project format (Legacy `SwiftCode/Frameworks/Internal/`,
/// Dylan's own code, ported under MIT): the manifest that describes a
/// SwiftCode project package, plus the on-disk project record. SwiftCode's
/// native project model is the real `.xcodeproj` / SwiftPM model in
/// `SwiftCodeProject`; this file exists so `.scproj` packages created by
/// Legacy SwiftCode can still be read, validated and re-written. ZIP
/// archives (`.scproj` as a single zipped file) are NOT supported here —
/// the destination has no ZIP dependency in this target — only directory
/// packages (see `SCProjectFormat.swift`).
///
/// Changes from Legacy, stated plainly:
/// - `Project` is renamed `SCProject` (the name is taken in other modules).
/// - `FileNode` is renamed `SCProjectFileNode` and drops its SwiftUI
///   `icon`/`iconColor` (a portable model must not import SwiftUI).
/// - The GitHub token field is dropped: Legacy kept it out of `project.json`
///   anyway ("stored in keychain, not persisted here") and the destination
///   keeps GitHub credentials in `SwiftCodeGitHub` / the `SecretStore`.
/// - `ProjectTransferConfiguration` (peer transfer) is not ported: its
///   `TransferPermission` / `TransferAuditEntry` types are outside this
///   slice and no transfer peer exists in the destination.

/// A comprehensive manifest for the .scproj project format (Legacy
/// `ProjectManifest`). All sections are optional-tolerant through memberwise
/// defaults at the call site; the synthesized `Codable` conformance reads
/// Legacy-written `manifest.json` files as-is.
public struct ProjectManifest: Codable, Sendable {
    public struct Identity: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var slug: String
        public var organizationName: String?
        public var organizationIdentifier: String?
        public var createdAt: Date
        public var updatedAt: Date
        public var lastOpenedAt: Date?
        public var description: String?
        public var category: String?
        public var tags: [String]
    }
    public var identity: Identity

    public struct BundleInfo: Codable, Sendable {
        public var bundleIdentifier: String
        public var bundleVersion: String
        public var bundleShortVersion: String
        public var displayName: String
        public var executableName: String
        public var copyright: String?
        public var principalClass: String?
    }
    public var bundle: BundleInfo

    public struct AppInfo: Codable, Sendable {
        public var appName: String
        public var appIconName: String?
        public var accentColorName: String?
        public var launchScreenName: String?
        public var supportedInterfaceOrientations: [String]
        public var requiresFullScreen: Bool
        public var statusBarStyle: String?
    }
    public var app: AppInfo

    public struct PackageInfo: Codable, Sendable {
        public var formatVersion: String
        public var packageType: String
        public var minSwiftVersion: String?
        public var toolsVersion: String?
        public var repositoryURL: String?
        public var license: String?
    }
    public var package: PackageInfo

    public struct BuildInfo: Codable, Sendable {
        public var defaultConfiguration: String
        public var configurations: [String]
        public var optimizationLevel: String?
        public var swiftCompilationMode: String?
        public var otherSwiftFlags: [String]
        public var otherLinkerFlags: [String]
        public var defines: [String: String]
    }
    public var build: BuildInfo

    public struct PlatformInfo: Codable, Sendable {
        public var targetPlatform: String
        public var deploymentTarget: String
        public var sdkVersion: String?
        public var architecture: [String]
        public var supportedDevices: [String]
    }
    public var platform: PlatformInfo

    public struct Versioning: Codable, Sendable {
        public var schemaVersion: Int
        public var migrationHistory: [MigrationEntry]

        public struct MigrationEntry: Codable, Sendable {
            public var fromVersion: Int
            public var toVersion: Int
            public var date: Date
            public var description: String
        }
    }
    public var versioning: Versioning

    public struct Statistics: Codable, Sendable {
        public var fileCount: Int
        public var directoryCount: Int
        public var totalSizeInBytes: Int64
        public var lineCount: Int
        public var codeLineCount: Int
        public var commentLineCount: Int
        public var assetCount: Int
        public var resourceCount: Int
    }
    public var statistics: Statistics

    public struct SourceMetadata: Codable, Sendable {
        public var mainEntryPath: String?
        public var sourceRoot: String
        public var moduleName: String
        public var importedModules: [String]
        public var headerSearchPaths: [String]
        public var frameworkSearchPaths: [String]
    }
    public var sourceCode: SourceMetadata

    public struct DependencyInfo: Codable, Sendable {
        public var frameworks: [Framework]
        public var externalPackages: [ExternalPackage]
        public var systemLibraries: [String]

        public struct Framework: Codable, Sendable {
            public var name: String
            public var path: String
            public var isEmbedded: Bool
        }

        public struct ExternalPackage: Codable, Sendable {
            public var name: String
            public var url: String
            public var versionRequirement: String
        }
    }
    public var dependencies: DependencyInfo

    public struct ResourceInfo: Codable, Sendable {
        public var assetCatalogs: [String]
        public var localizedResources: [String: [String]]
        public var fonts: [String]
        public var storyboards: [String]
        public var nibs: [String]
    }
    public var resources: ResourceInfo

    public struct StructureInfo: Codable, Sendable {
        public var roots: [String]
        public var ignoredPaths: [String]
        public var fileExclusions: [String]
        public var symlinks: [String: String]
    }
    public var structure: StructureInfo

    public struct SecurityInfo: Codable, Sendable {
        public var signingIdentity: String?
        public var provisioningProfile: String?
        public var entitlementsPath: String?
        public var hashAlgorithm: String
        public var manifestHash: String?
        public var packageIntegrityHash: String?
    }
    public var security: SecurityInfo

    public struct ValidationInfo: Codable, Sendable {
        public var lastValidationDate: Date?
        public var validationStatus: String
        public var issues: [ValidationIssue]

        public struct ValidationIssue: Codable, Sendable {
            public var severity: String
            public var message: String
            public var filePath: String?
        }
    }
    public var validation: ValidationInfo

    public struct FeatureFlags: Codable, Sendable {
        public var enabledFeatures: [String]
        public var capabilities: [String]
        public var entitlements: [String]
    }
    public var features: FeatureFlags

    public struct PerformanceMetrics: Codable, Sendable {
        public var lastBuildDuration: TimeInterval?
        public var averageBuildDuration: TimeInterval?
        public var indexSizeInBytes: Int64?
    }
    public var performance: PerformanceMetrics

    public struct ExtensionInfo: Codable, Sendable {
        public var activePlugins: [String]
        public var extensionPoints: [String]
        public var customMetadata: [String: String]
    }
    public var extensions: ExtensionInfo

    public struct InternalMetadata: Codable, Sendable {
        public var creatorTool: String
        public var creatorVersion: String
        public var internalFlags: [String: Bool]
        public var reserved: [String: String]
    }
    public var internalData: InternalMetadata

    public var extra: [String: String]

    public init(
        identity: Identity, bundle: BundleInfo, app: AppInfo, package: PackageInfo,
        build: BuildInfo, platform: PlatformInfo, versioning: Versioning,
        statistics: Statistics, sourceCode: SourceMetadata, dependencies: DependencyInfo,
        resources: ResourceInfo, structure: StructureInfo, security: SecurityInfo,
        validation: ValidationInfo, features: FeatureFlags, performance: PerformanceMetrics,
        extensions: ExtensionInfo, internalData: InternalMetadata, extra: [String: String] = [:]
    ) {
        self.identity = identity
        self.bundle = bundle
        self.app = app
        self.package = package
        self.build = build
        self.platform = platform
        self.versioning = versioning
        self.statistics = statistics
        self.sourceCode = sourceCode
        self.dependencies = dependencies
        self.resources = resources
        self.structure = structure
        self.security = security
        self.validation = validation
        self.features = features
        self.performance = performance
        self.extensions = extensions
        self.internalData = internalData
        self.extra = extra
    }
}

/// Project metadata written alongside the manifest (Legacy
/// `ProjectMetadata`).
public struct ProjectMetadata: Codable, Sendable {
    public var name: String
    public var description: String?
    public var author: String?
    public var version: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String, description: String? = nil, author: String? = nil, version: String = "1.0.0", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.name = name
        self.description = description
        self.author = author
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A file or folder in a `.scproj` package (Legacy `FileNode`, renamed).
public struct SCProjectFileNode: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Path relative to the project root.
    public var path: String
    public var isDirectory: Bool
    public var children: [SCProjectFileNode]
    public var isExpanded: Bool

    public enum CodingKeys: String, CodingKey {
        case id, name, path, isDirectory, children
    }

    public init(name: String, path: String, isDirectory: Bool, children: [SCProjectFileNode] = []) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
        self.isExpanded = false
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        children = try container.decode([SCProjectFileNode].self, forKey: .children)
        isExpanded = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(children, forKey: .children)
    }

    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    /// Every file node below this one, depth-first.
    public func flattenedFiles() -> [SCProjectFileNode] {
        if isDirectory {
            return children.flatMap { $0.flattenedFiles() }
        }
        return [self]
    }
}

/// The CI build configuration of a `.scproj` project (Legacy
/// `CIBuildConfiguration`).
public struct CIBuildConfiguration: Codable, Sendable {
    public enum Platform: String, Codable, CaseIterable, Sendable {
        case iOS
        case iOSAndIPadOS = "iOS + iPadOS"
    }

    public enum DeviceFamily: String, Codable, CaseIterable, Sendable {
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
        platform: Platform = .iOS, deploymentTarget: String = "16.0",
        targetDeviceFamily: DeviceFamily = .iPhoneAndIPad, schemeName: String = "Test",
        bundleIdentifier: String = "com.example.myapp"
    ) {
        self.platform = platform
        self.deploymentTarget = deploymentTarget
        self.targetDeviceFamily = targetDeviceFamily
        self.schemeName = schemeName
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Persisted per-project build metadata (Legacy `ProjectBuildSettings`).
/// All properties carry defaults so decoding tolerates older `project.json`
/// payloads that lack these keys.
public struct ProjectBuildSettings: Codable, Sendable {
    public var organizationName: String = ""
    public var bundleIdentifier: String = ""
    public var marketingVersion: String = "1.0.0"
    public var buildNumber: String = "1"
    public var autoIncrementBuildNumber: Bool = false
    public var developmentTeam: String = ""
    public var swiftLanguageVersion: String = "6.0"
    public var deploymentTargetPlatform: String = "macOS"
    public var deploymentTargetVersion: String = "15.0"
    public var buildConfigurationOverrides: [String]? = nil
    public var targetBundleIDOverrides: [String: String] = [:]
    public var xcodeSettings: [String: String] = [:]
    public var infoPlistPath: String = ""
    public var entitlementsPath: String = ""
    public var codeSignStyle: String = "Automatic"
    public var codeSignIdentity: String = ""
    public var provisioningProfileSpecifier: String = ""

    public init() {}
}

/// One `.scproj` project (Legacy `Project`, renamed `SCProject`).
/// `directoryURL` is the package directory itself; Legacy resolved a bare
/// name through a projects root, which the destination does not have, so
/// `SCProject` always carries its directory explicitly.
public struct SCProject: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var lastOpened: Date
    public var files: [SCProjectFileNode]
    public var githubRepo: String?
    public var description: String
    public var ciBuildConfiguration: CIBuildConfiguration?
    public var customDirectoryPath: String?
    public var destinations: [String]?
    public var buildSettings: ProjectBuildSettings
    public var fileCount: Int = 0

    /// The package directory. Legacy stored only a name and resolved it
    /// through `CodingManager.projectsRoot`; this port stores the directory
    /// on the record so a package can live anywhere.
    public var directoryURL: URL

    public enum CodingKeys: String, CodingKey {
        case id, name, createdAt, lastOpened, files, fileCount, githubRepo, description,
             ciBuildConfiguration, customDirectoryPath, destinations, buildSettings, directoryURL
    }

    public init(name: String, directoryURL: URL) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.lastOpened = Date()
        self.files = []
        self.fileCount = 0
        self.githubRepo = nil
        self.description = ""
        self.ciBuildConfiguration = CIBuildConfiguration()
        self.customDirectoryPath = nil
        self.destinations = ["iphonesimulator", "iphoneos", "macosx"]
        self.buildSettings = ProjectBuildSettings()
        self.directoryURL = directoryURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastOpened = try container.decode(Date.self, forKey: .lastOpened)
        // Legacy wrote an empty `files` array plus a `fileCount`; the tree
        // is rebuilt from disk by the deserializer, so decode tolerantly.
        files = (try? container.decode([SCProjectFileNode].self, forKey: .files)) ?? []
        fileCount = (try? container.decode(Int.self, forKey: .fileCount)) ?? 0
        githubRepo = try container.decodeIfPresent(String.self, forKey: .githubRepo)
        description = try container.decode(String.self, forKey: .description)
        ciBuildConfiguration = try container.decodeIfPresent(CIBuildConfiguration.self, forKey: .ciBuildConfiguration)
        customDirectoryPath = try container.decodeIfPresent(String.self, forKey: .customDirectoryPath)
        destinations = try container.decodeIfPresent([String].self, forKey: .destinations)
        buildSettings = try container.decodeIfPresent(ProjectBuildSettings.self, forKey: .buildSettings) ?? ProjectBuildSettings()
        if let customPath = customDirectoryPath {
            directoryURL = URL(fileURLWithPath: customPath)
        } else if let stored = try container.decodeIfPresent(URL.self, forKey: .directoryURL) {
            directoryURL = stored
        } else {
            directoryURL = URL(fileURLWithPath: name)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastOpened, forKey: .lastOpened)
        try container.encode([SCProjectFileNode](), forKey: .files)
        try container.encode(fileCount, forKey: .fileCount)
        try container.encode(githubRepo, forKey: .githubRepo)
        try container.encode(description, forKey: .description)
        try container.encode(ciBuildConfiguration, forKey: .ciBuildConfiguration)
        try container.encode(customDirectoryPath, forKey: .customDirectoryPath)
        try container.encodeIfPresent(destinations, forKey: .destinations)
        try container.encode(buildSettings, forKey: .buildSettings)
        try container.encode(directoryURL, forKey: .directoryURL)
    }

    public var displayName: String {
        directoryURL.lastPathComponent
    }
}

extension SCProject: Equatable {
    public static func == (lhs: SCProject, rhs: SCProject) -> Bool {
        lhs.id == rhs.id
    }
}
