import Foundation
import Observation
import SwiftCodeProject

/// Project Inspector — Legacy's `Views/Utilities/ProjectInspector/` subsystem
/// (scanner, architecture graph, inspector view), ported onto SwiftCode's systems.
///
/// - File metrics come from a real walk of the workspace (skipping `.git`,
///   `.build`, `DerivedData`, `xcuserdata`), with a JSON line-count cache
///   in Application Support `SwiftCode/ProjectInspector/<hash>/cache.json`
///   (Legacy kept the same cache in UserDefaults).
/// - Targets, schemes, build settings and package references come from
///   SwiftCode's own `PBXProj` parser — not a second pbxproj parser.
/// - The health score and recommendations are Legacy's
///   `calculateHealthAndRecommendations` rules, ported verbatim.
/// - The AI Review tab in the view takes a text provider (the coding
///   assistant's); with none configured it says so instead of inventing a
///   review. The health recommendations here are local and always real.

public struct FileMetrics: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: Int64
    public let lineCount: Int
    public init(name: String, path: String, size: Int64, lineCount: Int) {
        self.name = name; self.path = path; self.size = size; self.lineCount = lineCount
    }
}

public struct FolderMetrics: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let fileCount: Int
    public let totalSize: Int64
    public init(name: String, path: String, fileCount: Int, totalSize: Int64) {
        self.name = name; self.path = path; self.fileCount = fileCount; self.totalSize = totalSize
    }
}

public struct InspectorCacheEntry: Codable, Sendable {
    public let fileSize: Int64
    public let modificationDate: Date
    public let lineCount: Int
    public let swiftUI: Bool
    public let uikit: Bool
    public let appkit: Bool
    public let observation: Bool
    public let asyncAwait: Bool
    public let actorDefined: Bool
}

/// A build target discovered in the .xcodeproj, with per-configuration build settings.
public struct InspectorTargetInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public let name: String
    public let productType: String
    public let configurationNames: [String]
    public let buildSettings: [String: [String: String]]
    public init(id: String, name: String, productType: String, configurationNames: [String], buildSettings: [String: [String: String]]) {
        self.id = id; self.name = name; self.productType = productType
        self.configurationNames = configurationNames; self.buildSettings = buildSettings
    }
}

public struct InspectorSchemeInfo: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let isShared: Bool
    public init(name: String, isShared: Bool) {
        self.name = name; self.isShared = isShared
    }
}

public struct InspectorPackageInfo: Identifiable, Hashable, Sendable {
    public var id: String { url }
    public let name: String
    public let url: String
    public let isLocal: Bool
    public init(name: String, url: String, isLocal: Bool) {
        self.name = name; self.url = url; self.isLocal = isLocal
    }
}

/// Per-file detail (Legacy `InspectorFileMetadata`).
public struct InspectorFileMetadata: Sendable {
    public let url: URL
    public let size: Int64
    public let lineCount: Int
    public let imports: [String]
    public let localizations: [String]
    public let gitStatus: String

    public static func load(from url: URL, root: URL) -> InspectorFileMetadata? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = text.components(separatedBy: .newlines).count
        var imports: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                imports.append(String(trimmed.dropFirst("import ".count)).components(separatedBy: .whitespaces).first ?? "")
            }
        }
        return InspectorFileMetadata(
            url: url, size: size, lineCount: lines, imports: imports,
            localizations: localizations(for: url), gitStatus: gitStatus(for: url, root: root))
    }

    public static func localizations(for url: URL) -> [String] {
        let dir = url.deletingLastPathComponent()
        guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return children.filter { $0.pathExtension == "lproj" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    public static func gitStatus(for url: URL, root: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "status", "--porcelain", "--", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Unknown"
        }
        guard process.terminationStatus == 0 else { return "Unknown" }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Clean" }
        return String(trimmed.prefix(2))
    }
}

public enum InspectorGraphType: String, CaseIterable, Sendable, Identifiable {
    case files = "Files"
    case targets = "Targets"
    case packages = "Packages"
    public var id: String { rawValue }
}

public struct InspectorGraphNode: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let detail: String
    public let kind: String
    public init(name: String, detail: String, kind: String) {
        self.name = name; self.detail = detail; self.kind = kind
    }
}

/// The scanner (Legacy `InspectorProjectScanner`).
@Observable
@MainActor
public final class InspectorProjectScanner {
    public var projectName: String = ""
    public var bundleIdentifier: String = ""
    public var version: String = ""
    public var buildNumber: String = ""
    public var platformSupport: [String] = []
    public var deploymentTargets: [String: String] = [:]
    public var swiftVersion: String = ""
    public var sdkVersion: String = ""

    public var totalFiles: Int = 0
    public var totalFolders: Int = 0
    public var totalSwiftFiles: Int = 0
    public var totalAssets: Int = 0
    public var packageCount: Int = 0
    public var frameworkCount: Int = 0
    public var imageCount: Int = 0
    public var localizationCount: Int = 0
    public var jsonCount: Int = 0
    public var yamlCount: Int = 0
    public var plistCount: Int = 0
    public var markdownCount: Int = 0
    public var sqlCount: Int = 0

    public var largestFiles: [FileMetrics] = []
    public var longestSwiftFiles: [FileMetrics] = []
    public var largestFolders: [FolderMetrics] = []
    public var averageFileSize: Double = 0

    public var swiftUIUsageCount: Int = 0
    public var uikitUsageCount: Int = 0
    public var appkitUsageCount: Int = 0
    public var observationUsageCount: Int = 0
    public var asyncUsageCount: Int = 0
    public var actorUsageCount: Int = 0

    public var buildConfigurationSummary: String = ""
    public var projectHealthScore: Int = 100
    public var aiRecommendations: [String] = []
    public var isScanning: Bool = false

    public var projectDirectoryPath: String = ""
    public var xcodeProjectFound: Bool = false
    public var xcodeTargets: [InspectorTargetInfo] = []
    public var xcodeSchemes: [InspectorSchemeInfo] = []
    public var buildConfigurations: [String] = []
    public var packageDependencies: [InspectorPackageInfo] = []

    private var fileCache: [String: InspectorCacheEntry] = [:]
    private var cacheURL: URL?

    public init() {}

    public func scan(rootURL: URL) async {
        isScanning = true
        defer { isScanning = false }
        projectDirectoryPath = rootURL.path
        projectName = rootURL.lastPathComponent
        let hash = abs(rootURL.path.hashValue)
        let base: URL
        if IDEProcess.isTestProcess {
            base = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-inspector-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        }
        cacheURL = base.appendingPathComponent("SwiftCode/ProjectInspector/\(String(format: "%012x", hash))/cache.json")
        loadCache()
        let cacheSnapshot = fileCache
        let result = await Task.detached(priority: .userInitiated) {
            InspectorProjectScanner.performBackgroundScan(at: rootURL, cache: cacheSnapshot)
        }.value
        apply(result)
        saveCache()
    }

    private func apply(_ result: InspectorBackgroundScanResult) {
        totalFiles = result.totalFiles
        totalFolders = result.totalFolders
        totalSwiftFiles = result.totalSwiftFiles
        totalAssets = result.totalAssets
        packageCount = result.packageCount
        frameworkCount = result.frameworkCount
        imageCount = result.imageCount
        localizationCount = result.localizationCount
        jsonCount = result.jsonCount
        yamlCount = result.yamlCount
        plistCount = result.plistCount
        markdownCount = result.markdownCount
        sqlCount = result.sqlCount
        largestFiles = result.largestFiles
        longestSwiftFiles = result.longestSwiftFiles
        largestFolders = result.largestFolders
        averageFileSize = result.averageFileSize
        swiftUIUsageCount = result.swiftUIUsageCount
        uikitUsageCount = result.uikitUsageCount
        appkitUsageCount = result.appkitUsageCount
        observationUsageCount = result.observationUsageCount
        asyncUsageCount = result.asyncUsageCount
        actorUsageCount = result.actorUsageCount
        fileCache = result.cache
        let parsed = InspectorProjectScanner.parseXcodeProject(at: URL(fileURLWithPath: projectDirectoryPath))
        xcodeProjectFound = parsed.found
        xcodeTargets = parsed.targets
        xcodeSchemes = parsed.schemes
        buildConfigurations = parsed.configurations
        packageDependencies = parsed.packages
        bundleIdentifier = parsed.bundleIdentifier
        version = parsed.version
        buildNumber = parsed.buildNumber
        deploymentTargets = parsed.deploymentTargets
        buildConfigurationSummary = buildConfigurations.joined(separator: ", ")
        calculateHealthAndRecommendations()
    }

    /// Legacy's health rules, ported verbatim.
    private func calculateHealthAndRecommendations() {
        var score = 100
        var recs: [String] = []
        if averageFileSize > 1024 * 1024 {
            score -= 10
            recs.append("Average file size is extremely high. Consider compressing high-resolution assets or modularizing binary contents.")
        }
        let longFiles = longestSwiftFiles.filter { $0.lineCount > 1000 }
        if !longFiles.isEmpty {
            score -= min(15, longFiles.count * 3)
            recs.append("Detected \(longFiles.count) Swift files with over 1,000 lines (longest: \(longFiles.first?.name ?? "")). Splitting these long source files will improve compile-time performance.")
        }
        if actorUsageCount == 0 && totalSwiftFiles > 50 {
            score -= 5
            recs.append("No Actors detected in a project with \(totalSwiftFiles) Swift files. Consider utilizing actors to protect shared mutable state in concurrent flows.")
        }
        if observationUsageCount == 0 && swiftUIUsageCount > 10 {
            score -= 5
            recs.append("Your SwiftUI project doesn't use the Swift 5.9+ `@Observable` macro. Move away from legacy Combine ObservableObjects to prevent redundant UI layout updates.")
        }
        if localizationCount == 0 {
            score -= 8
            recs.append("No localization keys/catalogs found. Add localized strings or `.xcstrings` to expand international user support.")
        }
        let hugeFiles = largestFiles.filter { $0.size > 5 * 1024 * 1024 }
        if !hugeFiles.isEmpty {
            score -= min(10, hugeFiles.count * 2)
            recs.append("Found \(hugeFiles.count) files larger than 5MB on disk. Verify if they should be excluded from Git via `.gitignore` or tracked via LFS.")
        }
        if packageCount > 10 {
            recs.append("High number of Swift packages detected (\(packageCount)). Regularly audit dependencies to avoid duplicate library link mismatches.")
        }
        if recs.isEmpty {
            recs.append("Outstanding code composition! Keep maintaining modular components and leveraging modern Swift 6 paradigms.")
        }
        if !xcodeProjectFound {
            recs.append("No .xcodeproj was found at the project root, so target, scheme, and signing details are unavailable in the Project tab.")
        }
        projectHealthScore = max(30, score)
        aiRecommendations = recs
    }

    private func loadCache() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return }
        fileCache = (try? JSONDecoder().decode([String: InspectorCacheEntry].self, from: data)) ?? [:]
    }

    private func saveCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(fileCache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func graphNodes(for type: InspectorGraphType) -> [InspectorGraphNode] {
        switch type {
        case .files:
            return largestFolders.map { InspectorGraphNode(name: $0.name, detail: "\($0.fileCount) files · \(ByteCountFormatter.string(fromByteCount: $0.totalSize, countStyle: .file))", kind: "Folder") }
        case .targets:
            return xcodeTargets.map { InspectorGraphNode(name: $0.name, detail: $0.productType, kind: "Target") }
        case .packages:
            return packageDependencies.map { InspectorGraphNode(name: $0.name, detail: $0.url, kind: $0.isLocal ? "Local package" : "Remote package") }
        }
    }

    public func markdownReport() -> String {
        var lines = ["# Project Inspector — \(projectName)", ""]
        lines.append("Health score: \(projectHealthScore)/100")
        lines.append("Files: \(totalFiles) (\(totalSwiftFiles) Swift) · Folders: \(totalFolders) · Packages: \(packageCount)")
        lines.append("")
        lines.append("## Recommendations")
        for rec in aiRecommendations { lines.append("- \(rec)") }
        lines.append("")
        lines.append("## Largest files")
        for file in largestFiles.prefix(10) { lines.append("- \(file.path) — \(file.size) bytes, \(file.lineCount) lines") }
        return lines.joined(separator: "\n")
    }
}

public struct InspectorBackgroundScanResult: Sendable {
    public var totalFiles = 0
    public var totalFolders = 0
    public var totalSwiftFiles = 0
    public var totalAssets = 0
    public var packageCount = 0
    public var frameworkCount = 0
    public var imageCount = 0
    public var localizationCount = 0
    public var jsonCount = 0
    public var yamlCount = 0
    public var plistCount = 0
    public var markdownCount = 0
    public var sqlCount = 0
    public var largestFiles: [FileMetrics] = []
    public var longestSwiftFiles: [FileMetrics] = []
    public var largestFolders: [FolderMetrics] = []
    public var averageFileSize: Double = 0
    public var swiftUIUsageCount = 0
    public var uikitUsageCount = 0
    public var appkitUsageCount = 0
    public var observationUsageCount = 0
    public var asyncUsageCount = 0
    public var actorUsageCount = 0
    public var cache: [String: InspectorCacheEntry] = [:]
}

extension InspectorProjectScanner {
    nonisolated static func performBackgroundScan(at rootURL: URL, cache: [String: InspectorCacheEntry]) -> InspectorBackgroundScanResult {
        var result = InspectorBackgroundScanResult()
        result.cache = cache
        var allFiles: [FileMetrics] = []
        var folderStats: [String: (count: Int, size: Int64)] = [:]
        var totalSize: Int64 = 0
        let skipped: Set<String> = [".git", ".build", "DerivedData", "xcuserdata", "node_modules", ".swiftpm"]
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey]) else { return result }
        for case let fileURL as URL in enumerator {
            if skipped.contains(fileURL.lastPathComponent) { enumerator.skipDescendants(); continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey]) else { continue }
            if values.isDirectory == true {
                result.totalFolders += 1
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            let ext = fileURL.pathExtension.lowercased()
            result.totalFiles += 1
            totalSize += size
            switch ext {
            case "swift": result.totalSwiftFiles += 1
            case "xcassets": result.totalAssets += 1
            case "framework": result.frameworkCount += 1
            case "png", "jpg", "jpeg", "heic", "pdf": result.imageCount += 1
            case "xcstrings", "strings": result.localizationCount += 1
            case "json": result.jsonCount += 1
            case "yaml", "yml": result.yamlCount += 1
            case "plist": result.plistCount += 1
            case "md": result.markdownCount += 1
            case "sql": result.sqlCount += 1
            default: break
            }
            if ext == "swift" {
                let mtime = values.contentModificationDate ?? .distantPast
                if let cached = result.cache[fileURL.path], cached.fileSize == size, cached.modificationDate == mtime {
                    if cached.swiftUI { result.swiftUIUsageCount += 1 }
                    if cached.uikit { result.uikitUsageCount += 1 }
                    if cached.appkit { result.appkitUsageCount += 1 }
                    if cached.observation { result.observationUsageCount += 1 }
                    if cached.asyncAwait { result.asyncUsageCount += 1 }
                    if cached.actorDefined { result.actorUsageCount += 1 }
                    allFiles.append(FileMetrics(name: fileURL.lastPathComponent, path: fileURL.path, size: size, lineCount: cached.lineCount))
                } else if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let lines = text.components(separatedBy: .newlines).count
                    let entry = InspectorCacheEntry(
                        fileSize: size, modificationDate: mtime, lineCount: lines,
                        swiftUI: text.contains("import SwiftUI"), uikit: text.contains("import UIKit"),
                        appkit: text.contains("import AppKit"), observation: text.contains("@Observable"),
                        asyncAwait: text.contains("async ") || text.contains("await "),
                        actorDefined: text.contains("actor "))
                    result.cache[fileURL.path] = entry
                    if entry.swiftUI { result.swiftUIUsageCount += 1 }
                    if entry.uikit { result.uikitUsageCount += 1 }
                    if entry.appkit { result.appkitUsageCount += 1 }
                    if entry.observation { result.observationUsageCount += 1 }
                    if entry.asyncAwait { result.asyncUsageCount += 1 }
                    if entry.actorDefined { result.actorUsageCount += 1 }
                    allFiles.append(FileMetrics(name: fileURL.lastPathComponent, path: fileURL.path, size: size, lineCount: lines))
                }
            }
            let folder = fileURL.deletingLastPathComponent().path
            var stat = folderStats[folder] ?? (0, 0)
            stat.count += 1
            stat.size += size
            folderStats[folder] = stat
        }
        if fileURLIsPackage(rootURL) { result.packageCount += 1 }
        result.packageCount += countPackages(at: rootURL)
        result.largestFiles = allFiles.sorted { $0.size > $1.size }.prefix(20).map { $0 }
        result.longestSwiftFiles = allFiles.filter { $0.path.hasSuffix(".swift") }.sorted { $0.lineCount > $1.lineCount }.prefix(20).map { $0 }
        result.largestFolders = folderStats.map { FolderMetrics(name: URL(fileURLWithPath: $0.key).lastPathComponent, path: $0.key, fileCount: $0.value.count, totalSize: $0.value.size) }
            .sorted { $0.totalSize > $1.totalSize }.prefix(20).map { $0 }
        result.averageFileSize = result.totalFiles > 0 ? Double(totalSize) / Double(result.totalFiles) : 0
        return result
    }

    nonisolated private static func fileURLIsPackage(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
    }

    nonisolated private static func countPackages(at rootURL: URL) -> Int {
        // Packages referenced by .xcodeproj files and nested Package.swift manifests.
        var count = 0
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey]) else { return 0 }
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".git" || url.lastPathComponent == ".build" { enumerator.skipDescendants(); continue }
            if url.pathExtension == "xcodeproj" { count += 1; enumerator.skipDescendants() }
            else if url.lastPathComponent == "Package.swift" && url.deletingLastPathComponent() != rootURL { count += 1 }
        }
        return count
    }

    public struct XcodeProjectParseResult: Sendable {
        public var found = false
        public var targets: [InspectorTargetInfo] = []
        public var schemes: [InspectorSchemeInfo] = []
        public var configurations: [String] = []
        public var packages: [InspectorPackageInfo] = []
        public var bundleIdentifier = ""
        public var version = ""
        public var buildNumber = ""
        public var deploymentTargets: [String: String] = [:]
    }

    nonisolated static func parseXcodeProject(at rootURL: URL) -> XcodeProjectParseResult {
        var result = XcodeProjectParseResult()
        guard let children = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil),
              let xcodeproj = children.first(where: { $0.pathExtension == "xcodeproj" }) else { return result }
        result.found = true
        let pbxprojURL = xcodeproj.appendingPathComponent("project.pbxproj")
        guard let proj = try? PBXProj(contentsOf: pbxprojURL) else { return result }
        let configLists = proj.objects(isa: "XCBuildConfiguration")
        var configNames: [String] = []
        var settingsByConfig: [String: [String: String]] = [:]
        for config in configLists {
            let name = config.string("name") ?? ""
            if !name.isEmpty { configNames.append(name) }
            if let buildSettings = config.attributes["buildSettings"]?.dictionary {
                var flat: [String: String] = [:]
                for (key, value) in buildSettings { if let string = value.string { flat[key] = string } }
                settingsByConfig[name] = flat
            }
        }
        result.configurations = Array(Set(configNames)).sorted()
        let targets = proj.objects(isa: "PBXNativeTarget") + proj.objects(isa: "PBXAggregateTarget")
        for target in targets {
            let name = target.string("name") ?? target.string("productName") ?? "Untitled"
            let productType = target.string("productType") ?? ""
            let configListID = target.string("buildConfigurationList") ?? ""
            let configList = proj.objects(isa: "XCConfigurationList").first { $0.id == configListID }
            let configIDs = configList?.references("buildConfigurations") ?? []
            let names = configIDs.compactMap { id in configLists.first { $0.id == id }?.string("name") }
            var settings: [String: [String: String]] = [:]
            for configName in names { settings[configName] = settingsByConfig[configName] ?? [:] }
            result.targets.append(InspectorTargetInfo(id: target.id, name: name, productType: productType, configurationNames: names, buildSettings: settings))
            if result.bundleIdentifier.isEmpty {
                result.bundleIdentifier = settings.values.compactMap { $0["PRODUCT_BUNDLE_IDENTIFIER"] }.first ?? ""
            }
            if result.version.isEmpty {
                result.version = settings.values.compactMap { $0["MARKETING_VERSION"] }.first ?? ""
            }
            if result.buildNumber.isEmpty {
                result.buildNumber = settings.values.compactMap { $0["CURRENT_PROJECT_VERSION"] }.first ?? ""
            }
            for (configName, dict) in settings {
                if let target = dict["MACOSX_DEPLOYMENT_TARGET"] { result.deploymentTargets["macOS (\(configName))"] = target }
                if let target = dict["IPHONEOS_DEPLOYMENT_TARGET"] { result.deploymentTargets["iOS (\(configName))"] = target }
            }
        }
        for package in proj.objects(isa: "XCRemoteSwiftPackageReference") {
            let url = package.string("repositoryURL") ?? ""
            result.packages.append(InspectorPackageInfo(name: URL(string: url)?.lastPathComponent.replacingOccurrences(of: ".git", with: "") ?? url, url: url, isLocal: false))
        }
        for package in proj.objects(isa: "XCLocalSwiftPackageReference") {
            let path = package.string("relativePath") ?? ""
            result.packages.append(InspectorPackageInfo(name: URL(fileURLWithPath: path).lastPathComponent, url: path, isLocal: true))
        }
        let sharedSchemes = xcodeproj.appendingPathComponent("xcshareddata/xcschemes")
        if let schemes = try? FileManager.default.contentsOfDirectory(at: sharedSchemes, includingPropertiesForKeys: nil) {
            for scheme in schemes where scheme.pathExtension == "xcscheme" {
                result.schemes.append(InspectorSchemeInfo(name: scheme.deletingPathExtension().lastPathComponent, isShared: true))
            }
        }
        return result
    }
}
