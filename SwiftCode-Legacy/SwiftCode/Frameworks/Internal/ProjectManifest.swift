import Foundation

/// A comprehensive manifest for the .scproj project format.
/// This model contains extensive metadata fields covering every aspect of the project.
public struct ProjectManifest: Codable, Sendable {
    // MARK: - Core Identity
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

    // MARK: - Bundle Information
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

    // MARK: - Application Information
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

    // MARK: - Package Information
    public struct PackageInfo: Codable, Sendable {
        public var formatVersion: String
        public var packageType: String // e.g., "application", "framework", "library"
        public var minSwiftVersion: String?
        public var toolsVersion: String?
        public var repositoryURL: String?
        public var license: String?
    }
    public var package: PackageInfo

    // MARK: - Build Information
    public struct BuildInfo: Codable, Sendable {
        public var defaultConfiguration: String // e.g., "Debug", "Release"
        public var configurations: [String]
        public var optimizationLevel: String?
        public var swiftCompilationMode: String?
        public var otherSwiftFlags: [String]
        public var otherLinkerFlags: [String]
        public var defines: [String: String]
    }
    public var build: BuildInfo

    // MARK: - Platform Information
    public struct PlatformInfo: Codable, Sendable {
        public var targetPlatform: String // e.g., "macOS", "iOS"
        public var deploymentTarget: String
        public var sdkVersion: String?
        public var architecture: [String]
        public var supportedDevices: [String]
    }
    public var platform: PlatformInfo

    // MARK: - Versioning & Migration
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

    // MARK: - Statistics
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

    // MARK: - Source Code Metadata
    public struct SourceMetadata: Codable, Sendable {
        public var mainEntryPath: String?
        public var sourceRoot: String
        public var moduleName: String
        public var importedModules: [String]
        public var headerSearchPaths: [String]
        public var frameworkSearchPaths: [String]
    }
    public var sourceCode: SourceMetadata

    // MARK: - Frameworks & Dependencies
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

    // MARK: - Resources & Assets
    public struct ResourceInfo: Codable, Sendable {
        public var assetCatalogs: [String]
        public var localizedResources: [String: [String]] // Locale -> Paths
        public var fonts: [String]
        public var storyboards: [String]
        public var nibs: [String]
    }
    public var resources: ResourceInfo

    // MARK: - Directory & File Structure
    public struct StructureInfo: Codable, Sendable {
        public var roots: [String]
        public var ignoredPaths: [String]
        public var fileExclusions: [String]
        public var symlinks: [String: String]
    }
    public var structure: StructureInfo

    // MARK: - Security & Integrity
    public struct SecurityInfo: Codable, Sendable {
        public var signingIdentity: String?
        public var provisioningProfile: String?
        public var entitlementsPath: String?
        public var hashAlgorithm: String // e.g., "SHA-256"
        public var manifestHash: String?
        public var packageIntegrityHash: String?
    }
    public var security: SecurityInfo

    // MARK: - Diagnostics & Validation
    public struct ValidationInfo: Codable, Sendable {
        public var lastValidationDate: Date?
        public var validationStatus: String // "Valid", "Warning", "Invalid"
        public var issues: [ValidationIssue]

        public struct ValidationIssue: Codable, Sendable {
            public var severity: String // "Error", "Warning"
            public var message: String
            public var filePath: String?
        }
    }
    public var validation: ValidationInfo

    // MARK: - Features & Capabilities
    public struct FeatureFlags: Codable, Sendable {
        public var enabledFeatures: [String]
        public var capabilities: [String]
        public var entitlements: [String]
    }
    public var features: FeatureFlags

    // MARK: - Analytics & Performance
    public struct PerformanceMetrics: Codable, Sendable {
        public var lastBuildDuration: TimeInterval?
        public var averageBuildDuration: TimeInterval?
        public var indexSizeInBytes: Int64?
    }
    public var performance: PerformanceMetrics

    // MARK: - Plugin & Extension Metadata
    public struct ExtensionInfo: Codable, Sendable {
        public var activePlugins: [String]
        public var extensionPoints: [String]
        public var customMetadata: [String: String]
    }
    public var extensions: ExtensionInfo

    // MARK: - Internal & Reserved
    public struct InternalMetadata: Codable, Sendable {
        public var creatorTool: String
        public var creatorVersion: String
        public var internalFlags: [String: Bool]
        public var reserved: [String: String]
    }
    public var internalData: InternalMetadata

    // MARK: - Evolution & Expansion
    public var extra: [String: String] // For future expansion

    public init(
        identity: Identity,
        bundle: BundleInfo,
        app: AppInfo,
        package: PackageInfo,
        build: BuildInfo,
        platform: PlatformInfo,
        versioning: Versioning,
        statistics: Statistics,
        sourceCode: SourceMetadata,
        dependencies: DependencyInfo,
        resources: ResourceInfo,
        structure: StructureInfo,
        security: SecurityInfo,
        validation: ValidationInfo,
        features: FeatureFlags,
        performance: PerformanceMetrics,
        extensions: ExtensionInfo,
        internalData: InternalMetadata,
        extra: [String: String] = [:]
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
