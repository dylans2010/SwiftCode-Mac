import Foundation

public final class ManifestProjManager: Sendable {
    public static let shared = ManifestProjManager()
    private init() {}

    @MainActor
    public func createInitialManifest(for project: Project) -> ProjectManifest {
        let now = Date()
        let settings = AppSettings.shared

        let identity = ProjectManifest.Identity(
            id: project.id,
            name: project.name,
            slug: project.name.lowercased().replacingOccurrences(of: " ", with: "-"),
            organizationName: settings.fileHeaderAuthor,
            organizationIdentifier: "com.\(settings.fileHeaderAuthor.lowercased().replacingOccurrences(of: " ", with: ""))",
            createdAt: project.createdAt,
            updatedAt: now,
            lastOpenedAt: project.lastOpened,
            description: project.description,
            category: nil,
            tags: []
        )

        let bundle = ProjectManifest.BundleInfo(
            bundleIdentifier: project.ciBuildConfiguration?.bundleIdentifier ?? "com.swiftcode.\(identity.slug)",
            bundleVersion: "1",
            bundleShortVersion: "1.0",
            displayName: project.name,
            executableName: project.name,
            copyright: "Copyright © \(Calendar.current.component(.year, from: now))"
        )

        let app = ProjectManifest.AppInfo(
            appName: project.name,
            supportedInterfaceOrientations: ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
            requiresFullScreen: false
        )

        let package = ProjectManifest.PackageInfo(
            formatVersion: "1.0",
            packageType: "application"
        )

        let build = ProjectManifest.BuildInfo(
            defaultConfiguration: "Debug",
            configurations: ["Debug", "Release"],
            otherSwiftFlags: [],
            otherLinkerFlags: [],
            defines: [:]
        )

        let platform = ProjectManifest.PlatformInfo(
            targetPlatform: project.ciBuildConfiguration?.platform.rawValue ?? "iOS",
            deploymentTarget: project.ciBuildConfiguration?.deploymentTarget ?? "16.0",
            architecture: ["arm64", "x86_64"],
            supportedDevices: ["iPhone", "iPad"]
        )

        let versioning = ProjectManifest.Versioning(
            schemaVersion: ProjectVersionManager.shared.currentSchemaVersion,
            migrationHistory: []
        )

        let stats = calculateStatistics(for: project)
        let statistics = ProjectManifest.Statistics(
            fileCount: stats.fileCount,
            directoryCount: stats.directoryCount,
            totalSizeInBytes: stats.totalSize,
            lineCount: stats.totalLines,
            codeLineCount: stats.codeLines,
            commentLineCount: stats.commentLines,
            assetCount: stats.assetCount,
            resourceCount: stats.resourceCount
        )

        let sourceCode = ProjectManifest.SourceMetadata(
            sourceRoot: "Sources",
            moduleName: project.name,
            importedModules: ["SwiftUI"],
            headerSearchPaths: [],
            frameworkSearchPaths: []
        )

        let dependencies = ProjectManifest.DependencyInfo(
            frameworks: [],
            externalPackages: [],
            systemLibraries: []
        )

        let resources = ProjectManifest.ResourceInfo(
            assetCatalogs: [],
            localizedResources: [:],
            fonts: [],
            storyboards: [],
            nibs: []
        )

        let structure = ProjectManifest.StructureInfo(
            roots: ["Sources", "Resources"],
            ignoredPaths: [".DS_Store"],
            fileExclusions: [],
            symlinks: [:]
        )

        let security = ProjectManifest.SecurityInfo(
            hashAlgorithm: "SHA-256"
        )

        let validation = ProjectManifest.ValidationInfo(
            lastValidationDate: now,
            validationStatus: "Valid",
            issues: []
        )

        let features = ProjectManifest.FeatureFlags(
            enabledFeatures: [],
            capabilities: [],
            entitlements: []
        )

        let performance = ProjectManifest.PerformanceMetrics()

        let extensions = ProjectManifest.ExtensionInfo(
            activePlugins: [],
            extensionPoints: [],
            customMetadata: [:]
        )

        let internalData = ProjectManifest.InternalMetadata(
            creatorTool: "SwiftCode",
            creatorVersion: "1.0",
            internalFlags: [:],
            reserved: [:]
        )

        return ProjectManifest(
            identity: identity,
            bundle: bundle,
            app: app,
            package: package,
            build: build,
            platform: platform,
            versioning: versioning,
            statistics: statistics,
            sourceCode: sourceCode,
            dependencies: dependencies,
            resources: resources,
            structure: structure,
            security: security,
            validation: validation,
            features: features,
            performance: performance,
            extensions: extensions,
            internalData: internalData
        )
    }

    public func validateManifest(_ manifest: ProjectManifest) throws {
        guard !manifest.identity.name.isEmpty else {
            throw ProjectErrorManager.ProjectError.invalidFormat("Project name is empty in manifest")
        }

        guard !manifest.bundle.bundleIdentifier.isEmpty else {
            throw ProjectErrorManager.ProjectError.invalidFormat("Bundle identifier is empty in manifest")
        }

        if manifest.versioning.schemaVersion > ProjectVersionManager.shared.currentSchemaVersion {
            throw ProjectErrorManager.ProjectError.versionIncompatible(ProjectVersionManager.shared.currentSchemaVersion, manifest.versioning.schemaVersion)
        }
    }

    // MARK: - Private Helpers

    private struct CalcStats {
        var fileCount = 0
        var directoryCount = 0
        var totalSize: Int64 = 0
        var totalLines = 0
        var codeLines = 0
        var commentLines = 0
        var assetCount = 0
        var resourceCount = 0
    }

    @MainActor
    private func calculateStatistics(for project: Project) -> CalcStats {
        var stats = CalcStats()
        processNodes(project.files, in: project.directoryURL, into: &stats)
        return stats
    }

    @MainActor
    private func processNodes(_ nodes: [FileNode], in directoryURL: URL, into stats: inout CalcStats) {
        for node in nodes {
            if node.isDirectory {
                stats.directoryCount += 1
                processNodes(node.children, in: directoryURL, into: &stats)
            } else {
                stats.fileCount += 1

                let fileURL = directoryURL.appendingPathComponent(node.path)

                // Categorize based on extension and count lines
                let ext = node.fileExtension
                if ["swift", "h", "m", "c", "cpp"].contains(ext) {
                    if let content = try? String(contentsOf: fileURL) {
                        let lines = content.components(separatedBy: .newlines)
                        stats.totalLines += lines.count
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if trimmed.isEmpty { continue }
                            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                                stats.commentLines += 1
                            } else {
                                stats.codeLines += 1
                            }
                        }
                    }
                } else if ["xcassets", "png", "jpg", "pdf"].contains(ext) {
                    stats.assetCount += 1
                } else {
                    stats.resourceCount += 1
                }

                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
                    stats.totalSize += (attributes[.size] as? Int64) ?? 0
                }
            }
        }
    }
}
