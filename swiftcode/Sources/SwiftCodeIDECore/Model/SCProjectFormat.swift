import Foundation
import Observation
import Crypto

/// The `.scproj` package managers (Legacy
/// `SwiftCode/Frameworks/Internal/*ProjManager.swift`,
/// `ProjectCoordinator.swift`, `ProjectValidator.swift`,
/// `ProjectIntegrityManager.swift`, `ProjectHashManager.swift`, Dylan's own
/// code, ported under MIT). One directory package = `manifest.json` +
/// `metadata.json` + `project.json` + `project.xml` + `project.plist` +
/// `version.json` + `integrity.json` + `Sources/` + `Assets/` + `Resources/`.
///
/// Honest limits, stated plainly:
/// - ZIP archives are supported through the system tools, not
///   ZIPFoundation (which is not a dependency of this target):
///   `SCProjectArchive` zips with `/usr/bin/ditto -c -k` on macOS
///   (`zip` elsewhere) and unzips with `ditto -x -k` (`unzip`
///   elsewhere). `SCProjectCoordinator.exportProjectArchive` /
///   `importProjectArchive`, `getManifest(for:)`, and
///   `SCProjectValidator.validate(packageURL:)` all accept a
///   single-file archive URL exactly as Legacy's
///   `ProjectCoordinator` / `ProjectValidator` did (unpack to a temp
///   directory first). Directory packages work fully, unchanged.
/// - Hashing uses swift-crypto (`Crypto`) instead of Legacy's CryptoKit,
///   so this code builds on Linux too; the digests are the same SHA-256 /
///   SHA-512 values.
/// - `SCProjectXMLManager` writes the plist-XML encoding Legacy wrote
///   (its comment admitted it was a plist encoding, not a hand-written XML
///   schema); decoding accepts the same.

// MARK: - Errors

/// Package errors (Legacy `ProjectErrorManager.ProjectError`).
public enum SCProjectError: LocalizedError, Sendable {
    case manifestMissing
    case corruptedPackage(String)
    case invalidFormat(String)
    case versionIncompatible(Int, Int)
    case securityFailure(String)
    case ioError(Error)
    /// The project folder could not be found (Legacy
    /// `ProjectOpenError.pathNotFound`).
    case pathNotFound
    /// Loading took too long (Legacy `ProjectOpenError.timeout`).
    case timeout
    /// Loading was cancelled (Legacy `ProjectOpenError.cancelled`).
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .manifestMissing: return "The project manifest is missing."
        case .corruptedPackage(let message): return "The project package is corrupted: \(message)"
        case .invalidFormat(let message): return "Invalid file format: \(message)"
        case .versionIncompatible(let current, let required): return "Version mismatch: project requires version \(required), but only \(current) is supported."
        case .securityFailure(let message): return "Security verification failed: \(message)"
        case .ioError(let error): return "File system error: \(error.localizedDescription)"
        case .pathNotFound: return "The project folder could not be found."
        case .timeout: return "The project took too long to load. Please try again."
        case .cancelled: return "Project loading was cancelled."
        }
    }

    /// Logs a package error (Legacy `ProjectErrorManager.logError`).
    public static func logError(_ error: Error) {
        print("[SCProject] Error: \(error.localizedDescription)")
    }
}

/// ZIP archive support for `.scproj` packages (Legacy
/// `ProjectCoordinator` / `ProjectValidator` used ZIPFoundation's
/// `FileManager.zipItem` / `unzipItem`; this target has no ZIP
/// dependency, so the same operations go through the system tools).
public enum SCProjectArchive {
    /// Zips the directory at `sourceURL` into a single archive file
    /// at `destinationURL` (overwriting it when present).
    public static func zipItem(at sourceURL: URL, to destinationURL: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destinationURL)
        #if os(macOS)
        try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceURL.path, destinationURL.path])
        #else
        try run("/usr/bin/zip", ["-r", "-q", destinationURL.path, "."], currentDirectory: sourceURL)
        #endif
    }

    /// Unpacks the archive at `sourceURL` into the directory at
    /// `destinationURL` (created when missing).
    public static func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        #if os(macOS)
        try run("/usr/bin/ditto", ["-x", "-k", sourceURL.path, destinationURL.path])
        #else
        try run("/usr/bin/unzip", ["-q", sourceURL.path, "-d", destinationURL.path])
        #endif
    }

    private static func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        do {
            try process.run()
        } catch {
            throw SCProjectError.ioError(error)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SCProjectError.ioError(NSError(domain: "SwiftCode.SCProjectArchive", code: Int(process.terminationStatus),
                                                 userInfo: [NSLocalizedDescriptionKey: "\(executable) failed with status \(process.terminationStatus)."]))
        }
    }
}

// MARK: - File / JSON / plist / XML codecs

/// Plain file operations inside a package (Legacy `ProjectFileManager`).
public final class SCProjectFileManager: Sendable {
    public static let shared = SCProjectFileManager()
    private init() {}

    public func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeFile(data: Data, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }

    public func copyItem(at src: URL, to dst: URL) throws {
        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.copyItem(at: src, to: dst)
    }

    public func moveItem(at src: URL, to dst: URL) throws {
        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.moveItem(at: src, to: dst)
    }

    public func removeItem(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

/// JSON codec for package files (Legacy `ProjectJSONManager`): pretty
/// printed, sorted keys, ISO-8601 dates.
public final class SCProjectJSONManager: Sendable {
    public static let shared = SCProjectJSONManager()
    private init() {}

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    public func validate(data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}

/// Binary-plist codec (Legacy `ProjectPlistManager`).
public final class SCProjectPlistManager: Sendable {
    public static let shared = SCProjectPlistManager()
    private init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try PropertyListDecoder().decode(type, from: data)
    }

    public func validate(data: Data) -> Bool {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil
    }
}

/// XML codec (Legacy `ProjectXMLManager`): the plist-XML encoding, with a
/// real `XMLParser` validity check.
public final class SCProjectXMLManager: Sendable {
    public static let shared = SCProjectXMLManager()
    private init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(value)
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try PropertyListDecoder().decode(type, from: data)
    }

    public func validate(data: Data) -> Bool {
        XMLParser(data: data).parse()
    }
}

// MARK: - Hashing / versioning

/// SHA-256 / SHA-512 hashing (Legacy `ProjectHashManager`, CryptoKit
/// replaced by swift-crypto so this builds on Linux).
public final class SCProjectHashManager: Sendable {
    public static let shared = SCProjectHashManager()
    private init() {}

    public func hash(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func hash512(data: Data) -> String {
        SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func hashFile(at url: URL) throws -> String {
        hash(data: try Data(contentsOf: url))
    }

    public func compare(data: Data, with hash: String) -> Bool {
        self.hash(data: data) == hash
    }
}

/// Schema versioning (Legacy `ProjectVersionManager`). Current schema is 1;
/// migration appends a history entry per step, as Legacy did.
public final class SCProjectVersionManager: Sendable {
    public static let shared = SCProjectVersionManager()
    private init() {}

    public let currentSchemaVersion = 1

    public func checkCompatibility(manifest: ProjectManifest) -> Bool {
        manifest.versioning.schemaVersion <= currentSchemaVersion
    }

    public func migrateIfNeeded(_ manifest: inout ProjectManifest) throws {
        while manifest.versioning.schemaVersion < currentSchemaVersion {
            try migrateToNextVersion(&manifest)
        }
    }

    private func migrateToNextVersion(_ manifest: inout ProjectManifest) throws {
        let fromVersion = manifest.versioning.schemaVersion
        let toVersion = fromVersion + 1
        manifest.versioning.schemaVersion = toVersion
        manifest.versioning.migrationHistory.append(
            ProjectManifest.Versioning.MigrationEntry(
                fromVersion: fromVersion, toVersion: toVersion, date: Date(),
                description: "Migrated to version \(toVersion)"
            )
        )
    }
}

// MARK: - Package structure

/// Package directory layout (Legacy `ProjectPackageManager`).
public final class SCProjectPackageManager: Sendable {
    public static let shared = SCProjectPackageManager()
    private init() {}

    public func createPackageStructure(at url: URL) throws {
        for dir in ["Sources", "Assets", "Resources", "Settings", "Frameworks"] {
            try FileManager.default.createDirectory(at: url.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
    }

    public func validatePackageStructure(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return true
    }

    public func deletePackage(at url: URL) throws {
        try SCProjectFileManager.shared.removeItem(at: url)
    }

    public func duplicatePackage(at src: URL, to dst: URL) throws {
        try SCProjectFileManager.shared.copyItem(at: src, to: dst)
    }

    public func cleanupPackage(at url: URL) throws {
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator where fileURL.lastPathComponent == ".DS_Store" {
                try? fm.removeItem(at: fileURL)
            }
        }
        for sub in ["Sources", "Assets", "Resources", "Frameworks"] {
            removeEmptyDirectories(at: url.appendingPathComponent(sub))
        }
    }

    private func removeEmptyDirectories(at url: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for item in contents {
            removeEmptyDirectories(at: item)
        }
        if let remaining = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil), remaining.isEmpty,
           !["Sources", "Assets", "Resources", "Frameworks", "Settings"].contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }
}

/// Required resources inside a package (Legacy `ProjectResourceManager`).
public final class SCProjectResourceManager: Sendable {
    public static let shared = SCProjectResourceManager()
    private init() {}

    public func validateResources(at packageURL: URL) throws {
        for dir in ["Sources", "Resources"] {
            let dirURL = packageURL.appendingPathComponent(dir)
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir) || !isDir.boolValue {
                throw SCProjectError.corruptedPackage("Missing required directory: \(dir)")
            }
        }
    }

    public func copyResource(_ resourceURL: URL, to packageURL: URL) throws {
        let destURL = packageURL.appendingPathComponent("Resources").appendingPathComponent(resourceURL.lastPathComponent)
        try SCProjectFileManager.shared.copyItem(at: resourceURL, to: destURL)
    }
}

// MARK: - Integrity / validation

/// Manifest + package hash verification (Legacy `ProjectIntegrityManager`).
public final class SCProjectIntegrityManager: Sendable {
    public static let shared = SCProjectIntegrityManager()
    private init() {}

    public func verifyIntegrity(at packageURL: URL, manifest: ProjectManifest) throws -> Bool {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        if let expectedManifestHash = manifest.security.manifestHash {
            let manifestData = try Data(contentsOf: manifestURL)
            if SCProjectHashManager.shared.hash(data: manifestData) != expectedManifestHash {
                return false
            }
        }
        guard let expectedPackageHash = manifest.security.packageIntegrityHash else {
            return true
        }
        return try calculatePackageHash(at: packageURL) == expectedPackageHash
    }

    private func calculatePackageHash(at packageURL: URL) throws -> String {
        var combinedHash = ""
        if let enumerator = FileManager.default.enumerator(at: packageURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            var fileURLs: [URL] = []
            for case let fileURL as URL in enumerator {
                let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                if isFile, fileURL.lastPathComponent != "manifest.json", fileURL.lastPathComponent != "integrity.json" {
                    fileURLs.append(fileURL)
                }
            }
            fileURLs.sort { $0.path < $1.path }
            for url in fileURLs {
                combinedHash += try SCProjectHashManager.shared.hashFile(at: url)
            }
        }
        return combinedHash.isEmpty ? "" : SCProjectHashManager.shared.hash(data: combinedHash.data(using: .utf8)!)
    }

    /// Legacy's corruption check only ever verified that `manifest.json`
    /// exists; the name is kept, the behaviour is kept.
    public func detectCorruption(at packageURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("manifest.json").path)
    }
}

/// Full package validation (Legacy `ProjectValidator`). A
/// single-file URL is a zipped archive: it is unpacked to a temp
/// directory and validated there, exactly as Legacy did.
public final class SCProjectValidator: Sendable {
    public static let shared = SCProjectValidator()
    private init() {}

    public func validate(packageURL: URL) throws {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDir)
        if exists, !isDir.boolValue {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try SCProjectArchive.unzipItem(at: packageURL, to: tempDir)
            try validate(packageURL: tempDir)
            return
        }
        guard SCProjectPackageManager.shared.validatePackageStructure(at: packageURL) else {
            throw SCProjectError.corruptedPackage("Invalid directory structure")
        }
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        guard SCProjectFileManager.shared.exists(at: manifestURL) else {
            throw SCProjectError.manifestMissing
        }
        let manifestData = try SCProjectFileManager.shared.readFile(at: manifestURL)
        let manifest = try SCProjectJSONManager.shared.decode(ProjectManifest.self, from: manifestData)
        try SCProjectManifestManager.shared.validateManifest(manifest)
        guard SCProjectVersionManager.shared.checkCompatibility(manifest: manifest) else {
            throw SCProjectError.versionIncompatible(SCProjectVersionManager.shared.currentSchemaVersion, manifest.versioning.schemaVersion)
        }
        guard try SCProjectIntegrityManager.shared.verifyIntegrity(at: packageURL, manifest: manifest) else {
            throw SCProjectError.securityFailure("Integrity check failed")
        }
        try SCProjectResourceManager.shared.validateResources(at: packageURL)
    }
}

// MARK: - Manifest construction

/// Builds and validates manifests (Legacy `ManifestProjManager` +
/// `ProjectMetadataManager`). Legacy read the author from
/// `AppSettings.shared.fileHeaderAuthor`; this port takes the author as a
/// parameter so the portable model has no settings dependency.
public final class SCProjectManifestManager: Sendable {
    public static let shared = SCProjectManifestManager()
    private init() {}

    public func createInitialManifest(for project: SCProject, author: String = "") -> ProjectManifest {
        let now = Date()
        let slug = project.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let identity = ProjectManifest.Identity(
            id: project.id, name: project.name, slug: slug,
            organizationName: author.isEmpty ? nil : author,
            organizationIdentifier: author.isEmpty ? nil : "com.\(author.lowercased().replacingOccurrences(of: " ", with: ""))",
            createdAt: project.createdAt, updatedAt: now, lastOpenedAt: project.lastOpened,
            description: project.description.isEmpty ? nil : project.description, category: nil, tags: []
        )
        let bundle = ProjectManifest.BundleInfo(
            bundleIdentifier: project.ciBuildConfiguration?.bundleIdentifier ?? "com.swiftcode.\(slug)",
            bundleVersion: "1", bundleShortVersion: "1.0", displayName: project.name,
            executableName: project.name,
            copyright: "Copyright © \(Calendar.current.component(.year, from: now))",
            principalClass: nil
        )
        let app = ProjectManifest.AppInfo(
            appName: project.name, appIconName: nil, accentColorName: nil, launchScreenName: nil,
            supportedInterfaceOrientations: ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
            requiresFullScreen: false, statusBarStyle: nil
        )
        let package = ProjectManifest.PackageInfo(formatVersion: "1.0", packageType: "application", minSwiftVersion: nil, toolsVersion: nil, repositoryURL: nil, license: nil)
        let build = ProjectManifest.BuildInfo(
            defaultConfiguration: "Debug", configurations: ["Debug", "Release"],
            optimizationLevel: nil, swiftCompilationMode: nil, otherSwiftFlags: [], otherLinkerFlags: [], defines: [:]
        )
        let platform = ProjectManifest.PlatformInfo(
            targetPlatform: project.ciBuildConfiguration?.platform.rawValue ?? "iOS",
            deploymentTarget: project.ciBuildConfiguration?.deploymentTarget ?? "16.0",
            sdkVersion: nil, architecture: ["arm64", "x86_64"], supportedDevices: ["iPhone", "iPad"]
        )
        let versioning = ProjectManifest.Versioning(schemaVersion: SCProjectVersionManager.shared.currentSchemaVersion, migrationHistory: [])
        let statistics = calculateStatistics(for: project)
        let sourceCode = ProjectManifest.SourceMetadata(
            mainEntryPath: nil, sourceRoot: "Sources", moduleName: project.name,
            importedModules: ["SwiftUI"], headerSearchPaths: [], frameworkSearchPaths: []
        )
        let dependencies = ProjectManifest.DependencyInfo(frameworks: [], externalPackages: [], systemLibraries: [])
        let resources = ProjectManifest.ResourceInfo(assetCatalogs: [], localizedResources: [:], fonts: [], storyboards: [], nibs: [])
        let structure = ProjectManifest.StructureInfo(roots: ["Sources", "Resources"], ignoredPaths: [".DS_Store"], fileExclusions: [], symlinks: [:])
        let security = ProjectManifest.SecurityInfo(signingIdentity: nil, provisioningProfile: nil, entitlementsPath: nil, hashAlgorithm: "SHA-256", manifestHash: nil, packageIntegrityHash: nil)
        let validation = ProjectManifest.ValidationInfo(lastValidationDate: now, validationStatus: "Valid", issues: [])
        let features = ProjectManifest.FeatureFlags(enabledFeatures: [], capabilities: [], entitlements: [])
        let performance = ProjectManifest.PerformanceMetrics(lastBuildDuration: nil, averageBuildDuration: nil, indexSizeInBytes: nil)
        let extensions = ProjectManifest.ExtensionInfo(activePlugins: [], extensionPoints: [], customMetadata: [:])
        let internalData = ProjectManifest.InternalMetadata(creatorTool: "SwiftCode", creatorVersion: "1.0", internalFlags: [:], reserved: [:])
        return ProjectManifest(
            identity: identity, bundle: bundle, app: app, package: package, build: build,
            platform: platform, versioning: versioning, statistics: statistics, sourceCode: sourceCode,
            dependencies: dependencies, resources: resources, structure: structure, security: security,
            validation: validation, features: features, performance: performance,
            extensions: extensions, internalData: internalData
        )
    }

    public func generateMetadata(for project: SCProject, author: String = "") -> ProjectMetadata {
        ProjectMetadata(
            name: project.name,
            description: project.description.isEmpty ? nil : project.description,
            author: author.isEmpty ? nil : author,
            version: "1.0.0", createdAt: project.createdAt, updatedAt: Date()
        )
    }

    public func validateManifest(_ manifest: ProjectManifest) throws {
        guard !manifest.identity.name.isEmpty else {
            throw SCProjectError.invalidFormat("Project name is empty in manifest")
        }
        guard !manifest.bundle.bundleIdentifier.isEmpty else {
            throw SCProjectError.invalidFormat("Bundle identifier is empty in manifest")
        }
        if manifest.versioning.schemaVersion > SCProjectVersionManager.shared.currentSchemaVersion {
            throw SCProjectError.versionIncompatible(SCProjectVersionManager.shared.currentSchemaVersion, manifest.versioning.schemaVersion)
        }
    }

    public func calculateStatistics(for project: SCProject) -> ProjectManifest.Statistics {
        var fileCount = 0
        var directoryCount = 0
        var totalSize: Int64 = 0
        var totalLines = 0
        var codeLines = 0
        var commentLines = 0
        var assetCount = 0
        var resourceCount = 0
        // Count directories and files from the tree.
        func walk(_ nodes: [SCProjectFileNode]) {
            for node in nodes {
                if node.isDirectory {
                    directoryCount += 1
                    walk(node.children)
                } else {
                    fileCount += 1
                    let fileURL = project.directoryURL.appendingPathComponent(node.path)
                    if ["swift", "h", "m", "c", "cpp"].contains(node.fileExtension) {
                        if let content = try? String(contentsOf: fileURL) {
                            let lines = content.components(separatedBy: .newlines)
                            totalLines += lines.count
                            for line in lines {
                                let trimmed = line.trimmingCharacters(in: .whitespaces)
                                if trimmed.isEmpty { continue }
                                if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                                    commentLines += 1
                                } else {
                                    codeLines += 1
                                }
                            }
                        }
                    } else if ["xcassets", "png", "jpg", "pdf"].contains(node.fileExtension) {
                        assetCount += 1
                    } else {
                        resourceCount += 1
                    }
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
                        totalSize += (attributes[.size] as? Int64) ?? 0
                    }
                }
            }
        }
        walk(project.files)
        return ProjectManifest.Statistics(
            fileCount: fileCount, directoryCount: directoryCount, totalSizeInBytes: totalSize,
            lineCount: totalLines, codeLineCount: codeLines, commentLineCount: commentLines,
            assetCount: assetCount, resourceCount: resourceCount
        )
    }
}

// MARK: - Serialization

/// Writes a project into a directory package (Legacy `ProjectSerializer`).
public final class SCProjectSerializer: Sendable {
    public static let shared = SCProjectSerializer()
    private init() {}

    public func serialize(project: SCProject, to packageURL: URL) async throws {
        try SCProjectPackageManager.shared.createPackageStructure(at: packageURL)
        var manifest = SCProjectManifestManager.shared.createInitialManifest(for: project)
        let metadata = SCProjectManifestManager.shared.generateMetadata(for: project)
        let metadataData = try SCProjectJSONManager.shared.encode(metadata)
        try SCProjectFileManager.shared.writeFile(data: metadataData, to: packageURL.appendingPathComponent("metadata.json"))
        let projectData = try SCProjectJSONManager.shared.encode(project)
        try SCProjectFileManager.shared.writeFile(data: projectData, to: packageURL.appendingPathComponent("project.json"))
        let projectXML = try SCProjectXMLManager.shared.encode(project)
        try SCProjectFileManager.shared.writeFile(data: projectXML, to: packageURL.appendingPathComponent("project.xml"))
        let projectPlist = try SCProjectPlistManager.shared.encode(project)
        try SCProjectFileManager.shared.writeFile(data: projectPlist, to: packageURL.appendingPathComponent("project.plist"))
        let versionData = try SCProjectJSONManager.shared.encode(["schemaVersion": SCProjectVersionManager.shared.currentSchemaVersion])
        try SCProjectFileManager.shared.writeFile(data: versionData, to: packageURL.appendingPathComponent("version.json"))
        let sessionURL = project.directoryURL.appendingPathComponent("session.json")
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            try? FileManager.default.copyItem(at: sessionURL, to: packageURL.appendingPathComponent("session.json"))
        }
        try copyFiles(from: project, to: packageURL)
        try generateHashes(at: packageURL, manifest: &manifest)
        let manifestData = try SCProjectJSONManager.shared.encode(manifest)
        try SCProjectFileManager.shared.writeFile(data: manifestData, to: packageURL.appendingPathComponent("manifest.json"))
        let manifestHash = SCProjectHashManager.shared.hash(data: manifestData)
        let integrityData = try SCProjectJSONManager.shared.encode(["manifestHash": manifestHash])
        try SCProjectFileManager.shared.writeFile(data: integrityData, to: packageURL.appendingPathComponent("integrity.json"))
    }

    private func copyFiles(from project: SCProject, to packageURL: URL) throws {
        if project.files.isEmpty {
            // No tree recorded: copy the project's own bucket directories wholesale.
            for bucket in ["Sources", "Assets", "Resources"] {
                let source = project.directoryURL.appendingPathComponent(bucket)
                if FileManager.default.fileExists(atPath: source.path) {
                    try SCProjectFileManager.shared.copyItem(at: source, to: packageURL.appendingPathComponent(bucket))
                }
            }
            return
        }
        try distributeFiles(from: project.files, rootURL: project.directoryURL, packageURL: packageURL)
    }

    private func distributeFiles(from nodes: [SCProjectFileNode], rootURL: URL, packageURL: URL) throws {
        for node in nodes {
            if node.isDirectory {
                try distributeFiles(from: node.children, rootURL: rootURL, packageURL: packageURL)
                continue
            }
            let sourceURL = rootURL.appendingPathComponent(node.path)
            let ext = node.fileExtension
            let targetBucket: String
            if ["swift", "h", "m", "c", "cpp"].contains(ext) {
                targetBucket = "Sources"
            } else if ext == "xcassets" || sourceURL.path.contains(".xcassets") {
                targetBucket = "Assets"
            } else {
                targetBucket = "Resources"
            }
            let destPath: String
            if node.path.hasPrefix("\(targetBucket)/") {
                destPath = node.path
            } else {
                destPath = "\(targetBucket)/\(node.path)"
            }
            try SCProjectFileManager.shared.copyItem(at: sourceURL, to: packageURL.appendingPathComponent(destPath))
        }
    }

    private func generateHashes(at packageURL: URL, manifest: inout ProjectManifest) throws {
        var combinedHash = ""
        if let enumerator = FileManager.default.enumerator(at: packageURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            var fileURLs: [URL] = []
            for case let fileURL as URL in enumerator {
                let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                if isFile, fileURL.lastPathComponent != "manifest.json", fileURL.lastPathComponent != "integrity.json" {
                    fileURLs.append(fileURL)
                }
            }
            fileURLs.sort { $0.path < $1.path }
            for url in fileURLs {
                combinedHash += try SCProjectHashManager.shared.hashFile(at: url)
            }
        }
        if !combinedHash.isEmpty {
            manifest.security.packageIntegrityHash = SCProjectHashManager.shared.hash(data: combinedHash.data(using: .utf8)!)
        }
    }
}

/// Reads a directory package back into a project (Legacy
/// `ProjectDeserializer`). The file tree is rebuilt by scanning the
/// package's `Sources`/`Assets`/`Resources` buckets, because Legacy's
/// `project.json` records an empty `files` array.
public final class SCProjectDeserializer: Sendable {
    public static let shared = SCProjectDeserializer()
    private init() {}

    public func deserialize(from packageURL: URL) throws -> SCProject {
        try SCProjectValidator.shared.validate(packageURL: packageURL)
        let projectData = try SCProjectFileManager.shared.readFile(at: packageURL.appendingPathComponent("project.json"))
        var project = try SCProjectJSONManager.shared.decode(SCProject.self, from: projectData)
        let manifestData = try SCProjectFileManager.shared.readFile(at: packageURL.appendingPathComponent("manifest.json"))
        var manifest = try SCProjectJSONManager.shared.decode(ProjectManifest.self, from: manifestData)
        try SCProjectVersionManager.shared.migrateIfNeeded(&manifest)
        project.name = manifest.identity.name
        project.description = manifest.identity.description ?? ""
        project.createdAt = manifest.identity.createdAt
        project.lastOpened = Date()
        project.directoryURL = packageURL
        project.files = scanFileTree(at: packageURL)
        project.fileCount = project.files.flatMap { $0.flattenedFiles() }.count
        return project
    }

    private func scanFileTree(at packageURL: URL) -> [SCProjectFileNode] {
        var roots: [SCProjectFileNode] = []
        for bucket in ["Sources", "Assets", "Resources"] {
            let bucketURL = packageURL.appendingPathComponent(bucket)
            if let node = scanDirectory(at: bucketURL, relativePath: bucket) {
                roots.append(node)
            }
        }
        return roots
    }

    private func scanDirectory(at url: URL, relativePath: String) -> SCProjectFileNode? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        var children: [SCProjectFileNode] = []
        if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
                let childPath = "\(relativePath)/\(item.lastPathComponent)"
                if values?.isDirectory == true {
                    if let child = scanDirectory(at: item, relativePath: childPath) {
                        children.append(child)
                    }
                } else {
                    children.append(SCProjectFileNode(name: item.lastPathComponent, path: childPath, isDirectory: false))
                }
            }
        }
        return SCProjectFileNode(name: url.lastPathComponent, path: relativePath, isDirectory: true, children: children)
    }
}

// MARK: - Coordination / progress managers

/// Import/export orchestration (Legacy `ProjectCoordinator`).
/// Directory packages are exported/imported in place; the `*Archive`
/// variants produce and consume single-file ZIP archives, exactly as
/// Legacy's `exportProject` / `importProject` did.
public final class SCProjectCoordinator: Sendable {
    public static let shared = SCProjectCoordinator()
    private init() {}

    public func exportProject(_ project: SCProject, to destinationURL: URL) async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        let packageTempDir = tempDir.appendingPathComponent(project.name + ".scproj")
        try fm.createDirectory(at: packageTempDir, withIntermediateDirectories: true)
        try await SCProjectSerializer.shared.serialize(project: project, to: packageTempDir)
        try? fm.removeItem(at: destinationURL)
        try fm.moveItem(at: packageTempDir, to: destinationURL)
    }

    public func importProject(from packageURL: URL, into projectsRoot: URL) async throws -> SCProject {
        var project = try SCProjectDeserializer.shared.deserialize(from: packageURL)
        let fm = FileManager.default
        let sanitizedName = project.name
        var finalName = sanitizedName
        var destDir = projectsRoot.appendingPathComponent(finalName)
        var counter = 2
        while fm.fileExists(atPath: destDir.path) {
            finalName = "\(sanitizedName) \(counter)"
            destDir = projectsRoot.appendingPathComponent(finalName)
            counter += 1
        }
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(at: packageURL, includingPropertiesForKeys: nil)
        for item in contents {
            try fm.copyItem(at: item, to: destDir.appendingPathComponent(item.lastPathComponent))
        }
        project.name = finalName
        project.customDirectoryPath = nil
        project.directoryURL = destDir
        let projectData = try SCProjectJSONManager.shared.encode(project)
        try SCProjectFileManager.shared.writeFile(data: projectData, to: destDir.appendingPathComponent("project.json"))
        return project
    }

    /// Exports `project` as a single-file ZIP archive at
    /// `destinationURL` (Legacy `ProjectCoordinator.exportProject`:
    /// serialize into a temp folder, then zip it).
    public func exportProjectArchive(_ project: SCProject, to destinationURL: URL) async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        let packageTempDir = tempDir.appendingPathComponent(project.name + ".scproj")
        try fm.createDirectory(at: packageTempDir, withIntermediateDirectories: true)
        try await SCProjectSerializer.shared.serialize(project: project, to: packageTempDir)
        try SCProjectArchive.zipItem(at: packageTempDir, to: destinationURL)
    }

    /// Imports a single-file ZIP archive (or a directory package,
    /// which takes the existing `importProject` path) into
    /// `projectsRoot` (Legacy `ProjectCoordinator.importProject`:
    /// unpack to a temp folder first, then import from there).
    public func importProjectArchive(from packageURL: URL, into projectsRoot: URL) async throws -> SCProject {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDir)
        guard exists, !isDir.boolValue else {
            return try await importProject(from: packageURL, into: projectsRoot)
        }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try SCProjectArchive.unzipItem(at: packageURL, to: tempDir)
        return try await importProject(from: tempDir, into: projectsRoot)
    }

    public func validateProject(at packageURL: URL) throws {
        try SCProjectValidator.shared.validate(packageURL: packageURL)
    }

    public func getManifest(for packageURL: URL) throws -> ProjectManifest {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDir), !isDir.boolValue {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try SCProjectArchive.unzipItem(at: packageURL, to: tempDir)
            let manifestData = try SCProjectFileManager.shared.readFile(at: tempDir.appendingPathComponent("manifest.json"))
            return try SCProjectJSONManager.shared.decode(ProjectManifest.self, from: manifestData)
        }
        let manifestData = try SCProjectFileManager.shared.readFile(at: packageURL.appendingPathComponent("manifest.json"))
        return try SCProjectJSONManager.shared.decode(ProjectManifest.self, from: manifestData)
    }
}

/// Export progress state (Legacy `ExportProjManager`).
@Observable
@MainActor
public final class SCProjectExportManager {
    public static let shared = SCProjectExportManager()
    private init() {}

    public var exportProgress: Double = 0
    public var isExporting = false
    public var exportError: Error?

    public func exportProject(_ project: SCProject, to url: URL) async throws {
        isExporting = true
        exportProgress = 0
        exportError = nil
        defer { isExporting = false }
        do {
            exportProgress = 0.3
            try await SCProjectCoordinator.shared.exportProject(project, to: url)
            exportProgress = 1.0
        } catch {
            exportError = error
            throw error
        }
    }
}

/// Import progress state (Legacy `ImportProjManager`).
@Observable
@MainActor
public final class SCProjectImportManager {
    public static let shared = SCProjectImportManager()
    private init() {}

    public var importProgress: Double = 0
    public var isImporting = false
    public var importError: Error?

    public func importProject(from url: URL, into projectsRoot: URL) async throws -> SCProject {
        isImporting = true
        importProgress = 0
        importError = nil
        defer { isImporting = false }
        do {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            importProgress = 0.2
            try SCProjectValidator.shared.validate(packageURL: url)
            importProgress = 0.5
            let project = try await SCProjectCoordinator.shared.importProject(from: url, into: projectsRoot)
            importProgress = 1.0
            return project
        } catch {
            importError = error
            throw error
        }
    }
}
