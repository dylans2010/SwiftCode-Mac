import Foundation
import os
import SwiftUI
import Observation

private let logger = Logger(subsystem: "com.swiftcode.app", category: "ProjectScanner")

public struct FileMetrics: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: Int64
    public let lineCount: Int
}

public struct FolderMetrics: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let fileCount: Int
    public let totalSize: Int64
}

public struct CacheEntry: Codable, Sendable {
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

// MARK: - Xcode Project Models (parsed from project.pbxproj)

/// A build target discovered in the .xcodeproj, with per-configuration build settings.
public struct InspectorTargetInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public let name: String
    public let productType: String
    public let configurationNames: [String]
    /// Configuration name -> build setting key -> value
    public let buildSettings: [String: [String: String]]
}

/// An Xcode scheme discovered next to the .xcodeproj.
public struct InspectorSchemeInfo: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let isShared: Bool
}

/// A Swift package dependency referenced by the .xcodeproj.
public struct InspectorPackageInfo: Identifiable, Hashable, Sendable {
    public var id: String { url }
    public let name: String
    public let url: String
    public let isLocal: Bool
}

@Observable
@MainActor
public final class InspectorProjectScanner {
    public static let shared = InspectorProjectScanner()

    public var projectName: String = "SwiftCode"
    public var bundleIdentifier: String = "com.SwiftCode"
    public var version: String = "1.0.0"
    public var buildNumber: String = "1"
    public var platformSupport: [String] = ["macOS"]
    public var deploymentTargets: [String: String] = ["macOS": "15.0"]
    public var swiftVersion: String = "6.0"
    public var sdkVersion: String = "macOS 15+"

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

    public var recentChanges: [String] = []
    public var largestFiles: [FileMetrics] = []
    public var longestSwiftFiles: [FileMetrics] = []
    public var largestFolders: [FolderMetrics] = []
    public var averageFileSize: Double = 0.0

    public var swiftUIUsageCount: Int = 0
    public var uikitUsageCount: Int = 0
    public var appkitUsageCount: Int = 0
    public var observationUsageCount: Int = 0
    public var asyncUsageCount: Int = 0
    public var actorUsageCount: Int = 0

    public var buildConfigurationSummary: String = "Release"
    public var projectHealthScore: Int = 100
    public var aiRecommendations: [String] = []
    public var isScanning: Bool = false

    // MARK: - Xcode project structure (parsed from project.pbxproj)

    public var projectDirectoryPath: String = ""
    public var xcodeProjectFound: Bool = false
    public var xcodeTargets: [InspectorTargetInfo] = []
    public var xcodeSchemes: [InspectorSchemeInfo] = []
    public var buildConfigurations: [String] = []
    public var packageDependencies: [InspectorPackageInfo] = []

    // Scanner file cache (persistence via UserDefaults)
    private var fileCache: [String: CacheEntry] = [:]

    private init() {
        loadCache()
    }

    public func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        logger.log("Starting background project scan...")

        // Direct linkage to the active project currently open in the workspace!
        let url: URL
        if let activeProject = ProjectSessionStore.shared.activeProject {
            url = activeProject.directoryURL
        } else {
            let rootPath = FileManager.default.currentDirectoryPath
            url = URL(fileURLWithPath: rootPath)
        }

        // Read plist or project config info
        self.projectName = url.lastPathComponent
        if self.projectName.isEmpty || self.projectName == "." {
            self.projectName = "SwiftCode"
        }

        // Run scanning on background task
        let cachedFiles = fileCache
        self.projectDirectoryPath = url.path
        let metrics = await Task.detached(priority: .userInitiated) {
            return InspectorProjectScanner.performBackgroundScan(at: url, cache: cachedFiles)
        }.value

        // Update state
        self.projectName = metrics.projectName
        self.totalFiles = metrics.totalFiles
        self.totalFolders = metrics.totalFolders
        self.totalSwiftFiles = metrics.totalSwiftFiles
        self.totalAssets = metrics.totalAssets
        self.packageCount = metrics.packageCount
        self.frameworkCount = metrics.frameworkCount
        self.imageCount = metrics.imageCount
        self.localizationCount = metrics.localizationCount
        self.jsonCount = metrics.jsonCount
        self.yamlCount = metrics.yamlCount
        self.plistCount = metrics.plistCount
        self.markdownCount = metrics.markdownCount
        self.sqlCount = metrics.sqlCount

        self.largestFiles = metrics.largestFiles
        self.longestSwiftFiles = metrics.longestSwiftFiles
        self.largestFolders = metrics.largestFolders
        self.averageFileSize = metrics.averageFileSize

        self.swiftUIUsageCount = metrics.swiftUIUsageCount
        self.uikitUsageCount = metrics.uikitUsageCount
        self.appkitUsageCount = metrics.appkitUsageCount
        self.observationUsageCount = metrics.observationUsageCount
        self.asyncUsageCount = metrics.asyncUsageCount
        self.actorUsageCount = metrics.actorUsageCount

        self.recentChanges = metrics.recentChanges

        // Xcode project structure
        self.xcodeProjectFound = metrics.xcodeProjectFound
        self.xcodeTargets = metrics.xcodeTargets
        self.xcodeSchemes = metrics.xcodeSchemes
        self.buildConfigurations = metrics.buildConfigurations
        self.packageDependencies = metrics.packageDependencies
        if !metrics.buildConfigurations.isEmpty {
            self.buildConfigurationSummary = metrics.buildConfigurations.joined(separator: ", ")
        }

        // Save cache updates
        self.fileCache = metrics.newCache
        saveCache()

        // Calculate Project Health & AI Recommendations
        calculateHealthAndRecommendations()
        logger.log("Project scan complete!")
    }

    private struct BackgroundScanResult: Sendable {
        let projectName: String
        let totalFiles: Int
        let totalFolders: Int
        let totalSwiftFiles: Int
        let totalAssets: Int
        let packageCount: Int
        let frameworkCount: Int
        let imageCount: Int
        let localizationCount: Int
        let jsonCount: Int
        let yamlCount: Int
        let plistCount: Int
        let markdownCount: Int
        let sqlCount: Int

        let largestFiles: [FileMetrics]
        let longestSwiftFiles: [FileMetrics]
        let largestFolders: [FolderMetrics]
        let averageFileSize: Double

        let swiftUIUsageCount: Int
        let uikitUsageCount: Int
        let appkitUsageCount: Int
        let observationUsageCount: Int
        let asyncUsageCount: Int
        let actorUsageCount: Int

        let recentChanges: [String]
        let newCache: [String: CacheEntry]

        let xcodeProjectFound: Bool
        let xcodeTargets: [InspectorTargetInfo]
        let xcodeSchemes: [InspectorSchemeInfo]
        let buildConfigurations: [String]
        let packageDependencies: [InspectorPackageInfo]
    }

    nonisolated private static func performBackgroundScan(at rootURL: URL, cache: [String: CacheEntry]) -> BackgroundScanResult {
        let fileManager = FileManager.default
        var localCache = cache

        var totalFiles = 0
        var totalFolders = 0
        var totalSwiftFiles = 0
        var totalAssets = 0
        var packageCount = 0
        var frameworkCount = 0
        var imageCount = 0
        var localizationCount = 0
        var jsonCount = 0
        var yamlCount = 0
        var plistCount = 0
        var markdownCount = 0
        var sqlCount = 0

        var swiftUIUsageCount = 0
        var uikitUsageCount = 0
        var appkitUsageCount = 0
        var observationUsageCount = 0
        var asyncUsageCount = 0
        var actorUsageCount = 0

        var allFiles: [FileMetrics] = []
        var swiftFiles: [FileMetrics] = []
        var foldersMap: [String: (fileCount: Int, totalSize: Int64)] = [:]

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return BackgroundScanResult(
                projectName: "SwiftCode", totalFiles: 0, totalFolders: 0, totalSwiftFiles: 0, totalAssets: 0,
                packageCount: 0, frameworkCount: 0, imageCount: 0, localizationCount: 0, jsonCount: 0,
                yamlCount: 0, plistCount: 0, markdownCount: 0, sqlCount: 0, largestFiles: [],
                longestSwiftFiles: [], largestFolders: [], averageFileSize: 0, swiftUIUsageCount: 0,
                uikitUsageCount: 0, appkitUsageCount: 0, observationUsageCount: 0, asyncUsageCount: 0,
                actorUsageCount: 0, recentChanges: [], newCache: cache,
                xcodeProjectFound: false, xcodeTargets: [], xcodeSchemes: [],
                buildConfigurations: [], packageDependencies: []
            )
        }

        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            let isDirectory = resourceValues.isDirectory ?? false

            if isDirectory {
                totalFolders += 1
                // Count frameworks
                if fileURL.pathExtension == "framework" || fileURL.pathExtension == "xcframework" {
                    frameworkCount += 1
                }
                continue
            }

            totalFiles += 1
            let size = Int64(resourceValues.fileSize ?? 0)
            totalBytes += size

            let path = fileURL.path
            let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")

            // Folder analysis
            let parentFolder = fileURL.deletingLastPathComponent().path
            let parentRelativePath = parentFolder.replacingOccurrences(of: rootURL.path + "/", with: "")
            let entry = foldersMap[parentRelativePath] ?? (0, 0)
            foldersMap[parentRelativePath] = (entry.fileCount + 1, entry.totalSize + size)

            // Extension grouping
            let ext = fileURL.pathExtension.lowercased()
            if ext == "swift" {
                totalSwiftFiles += 1
            } else if ext == "json" {
                jsonCount += 1
            } else if ext == "yaml" || ext == "yml" {
                yamlCount += 1
            } else if ext == "sql" {
                sqlCount += 1
            } else if ext == "md" {
                markdownCount += 1
            } else if ext == "plist" {
                plistCount += 1
            } else if ext == "strings" || ext == "stringsdict" || ext == "xcstrings" {
                localizationCount += 1
            } else if ["png", "jpg", "jpeg", "webp", "pdf"].contains(ext) {
                imageCount += 1
            }

            if fileURL.path.contains(".xcassets") {
                totalAssets += 1
            }
            if fileURL.lastPathComponent == "Package.swift" {
                packageCount += 1
            }

            // Line & content analysis (Swift files)
            var lines = 0
            var swiftUI = false
            var uikit = false
            var appkit = false
            var observation = false
            var asyncAwait = false
            var actorDefined = false

            if ext == "swift" {
                let modDate = resourceValues.contentModificationDate ?? Date()

                if let cached = localCache[path], cached.fileSize == size, cached.modificationDate == modDate {
                    lines = cached.lineCount
                    swiftUI = cached.swiftUI
                    uikit = cached.uikit
                    appkit = cached.appkit
                    observation = cached.observation
                    asyncAwait = cached.asyncAwait
                    actorDefined = cached.actorDefined
                } else {
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        let contentLines = content.components(separatedBy: .newlines)
                        lines = contentLines.count

                        swiftUI = content.contains("import SwiftUI") || content.contains(": View")
                        uikit = content.contains("import UIKit") || content.contains("UIViewController")
                        appkit = content.contains("import AppKit") || content.contains("NSViewController")
                        observation = content.contains("@Observable")
                        asyncAwait = content.contains("async") && content.contains("await")
                        actorDefined = content.contains("actor ")

                        // Cache update
                        localCache[path] = CacheEntry(
                            fileSize: size,
                            modificationDate: modDate,
                            lineCount: lines,
                            swiftUI: swiftUI,
                            uikit: uikit,
                            appkit: appkit,
                            observation: observation,
                            asyncAwait: asyncAwait,
                            actorDefined: actorDefined
                        )
                    }
                }

                if swiftUI { swiftUIUsageCount += 1 }
                if uikit { uikitUsageCount += 1 }
                if appkit { appkitUsageCount += 1 }
                if observation { observationUsageCount += 1 }
                if asyncAwait { asyncUsageCount += 1 }
                if actorDefined { actorUsageCount += 1 }
            }

            let fileMetric = FileMetrics(name: fileURL.lastPathComponent, path: relativePath, size: size, lineCount: lines)
            allFiles.append(fileMetric)
            if ext == "swift" {
                swiftFiles.append(fileMetric)
            }
        }

        let largestFiles = Array(allFiles.sorted(by: { $0.size > $1.size }).prefix(10))
        let longestSwiftFiles = Array(swiftFiles.sorted(by: { $0.lineCount > $1.lineCount }).prefix(10))

        let largestFolders = Array(foldersMap.map { FolderMetrics(name: $0.key.isEmpty ? "Root" : ($0.key as NSString).lastPathComponent, path: $0.key, fileCount: $0.value.fileCount, totalSize: $0.value.totalSize) }
            .sorted(by: { $0.totalSize > $1.totalSize })
            .prefix(10))

        let averageFileSize = totalFiles > 0 ? Double(totalBytes) / Double(totalFiles) : 0.0

        // Fetch recent changes using git command if available
        var recentChangesList: [String] = []
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["log", "-n", "5", "--oneline"]
        let pipe = Pipe()
        process.standardOutput = pipe
        if (try? process.run()) != nil {
            process.waitUntilExit()
            if let data = try? pipe.fileHandleForReading.readToEnd(),
               let str = String(data: data, encoding: .utf8) {
                recentChangesList = str.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
        }

        if recentChangesList.isEmpty {
            recentChangesList = ["Initial scan baseline completed."]
        }

        let projName = rootURL.lastPathComponent.isEmpty ? "SwiftCode" : rootURL.lastPathComponent

        // Parse the .xcodeproj for targets, schemes, configurations, and packages.
        let xcode = parseXcodeProject(at: rootURL)

        return BackgroundScanResult(
            projectName: projName,
            totalFiles: totalFiles,
            totalFolders: totalFolders,
            totalSwiftFiles: totalSwiftFiles,
            totalAssets: totalAssets,
            packageCount: packageCount,
            frameworkCount: frameworkCount,
            imageCount: imageCount,
            localizationCount: localizationCount,
            jsonCount: jsonCount,
            yamlCount: yamlCount,
            plistCount: plistCount,
            markdownCount: markdownCount,
            sqlCount: sqlCount,
            largestFiles: largestFiles,
            longestSwiftFiles: longestSwiftFiles,
            largestFolders: largestFolders,
            averageFileSize: averageFileSize,
            swiftUIUsageCount: swiftUIUsageCount,
            uikitUsageCount: uikitUsageCount,
            appkitUsageCount: appkitUsageCount,
            observationUsageCount: observationUsageCount,
            asyncUsageCount: asyncUsageCount,
            actorUsageCount: actorUsageCount,
            recentChanges: recentChangesList,
            newCache: localCache,
            xcodeProjectFound: xcode.found,
            xcodeTargets: xcode.targets,
            xcodeSchemes: xcode.schemes,
            buildConfigurations: xcode.configurations,
            packageDependencies: xcode.packages
        )
    }

    // MARK: - Xcode Project Parsing

    private struct XcodeProjectParseResult: Sendable {
        let found: Bool
        let targets: [InspectorTargetInfo]
        let schemes: [InspectorSchemeInfo]
        let configurations: [String]
        let packages: [InspectorPackageInfo]
    }

    /// Locates the .xcodeproj under the project root and extracts targets,
    /// build configurations + settings, schemes, and package dependencies.
    nonisolated private static func parseXcodeProject(at rootURL: URL) -> XcodeProjectParseResult {
        let fileManager = FileManager.default

        // Find the .xcodeproj at the root or one level down.
        var xcodeprojURL: URL? = nil
        if let contents = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            xcodeprojURL = contents.first(where: { $0.pathExtension == "xcodeproj" && $0.hasDirectoryPath })
            if xcodeprojURL == nil {
                for dir in contents where dir.hasDirectoryPath {
                    if let sub = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
                       let found = sub.first(where: { $0.pathExtension == "xcodeproj" && $0.hasDirectoryPath }) {
                        xcodeprojURL = found
                        break
                    }
                }
            }
        }

        guard let projURL = xcodeprojURL else {
            return XcodeProjectParseResult(found: false, targets: [], schemes: [], configurations: [], packages: [])
        }

        var targets: [InspectorTargetInfo] = []
        var configurationNames: [String] = []
        var packages: [InspectorPackageInfo] = []

        let pbxprojURL = projURL.appendingPathComponent("project.pbxproj")
        if let data = try? Data(contentsOf: pbxprojURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let objects = plist["objects"] as? [String: Any] {

            // Package dependencies (remote + local).
            for (_, obj) in objects {
                guard let dict = obj as? [String: Any], let isa = dict["isa"] as? String else { continue }
                if isa == "XCRemoteSwiftPackageReference", let repo = dict["repositoryURL"] as? String {
                    let name = URL(string: repo)?.deletingPathExtension().lastPathComponent ?? repo
                    packages.append(InspectorPackageInfo(name: name.isEmpty ? repo : name, url: repo, isLocal: false))
                } else if isa == "XCLocalSwiftPackageReference", let relPath = dict["relativePath"] as? String {
                    let name = (relPath as NSString).lastPathComponent
                    packages.append(InspectorPackageInfo(name: name.isEmpty ? relPath : name, url: relPath, isLocal: true))
                }
            }

            // Targets with their build configurations and settings.
            for (_, obj) in objects {
                guard let dict = obj as? [String: Any],
                      let isa = dict["isa"] as? String,
                      isa == "PBXNativeTarget" || isa == "PBXAggregateTarget",
                      let name = dict["name"] as? String else { continue }

                let productTypeRaw = dict["productType"] as? String ?? ""
                let productType = productTypeLabel(productTypeRaw)
                var settingsByConfig: [String: [String: String]] = [:]

                if let listID = dict["buildConfigurationList"] as? String,
                   let list = objects[listID] as? [String: Any],
                   let configIDs = list["buildConfigurations"] as? [String] {
                    for configID in configIDs {
                        guard let config = objects[configID] as? [String: Any],
                              let configName = config["name"] as? String else { continue }
                        if !configurationNames.contains(configName) {
                            configurationNames.append(configName)
                        }
                        var flat: [String: String] = [:]
                        if let buildSettings = config["buildSettings"] as? [String: Any] {
                            for (key, value) in buildSettings {
                                flat[key] = plistScalarString(value)
                            }
                        }
                        settingsByConfig[configName] = flat
                    }
                }

                targets.append(InspectorTargetInfo(
                    id: name + "|" + productTypeRaw,
                    name: name,
                    productType: productType,
                    configurationNames: settingsByConfig.keys.sorted(),
                    buildSettings: settingsByConfig
                ))
            }
        }

        // Schemes (shared first-class citizens, plus user schemes).
        var schemes: [InspectorSchemeInfo] = []
        let schemeDirs = [
            projURL.appendingPathComponent("xcshareddata/xcschemes"),
            projURL.appendingPathComponent("xcuserdata")
        ]
        for dir in schemeDirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator where fileURL.pathExtension == "xcscheme" {
                    let isShared = fileURL.path.contains("xcshareddata")
                    let name = fileURL.deletingPathExtension().lastPathComponent
                    if !schemes.contains(where: { $0.name == name }) {
                        schemes.append(InspectorSchemeInfo(name: name, isShared: isShared))
                    }
                }
            }
        }

        targets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        schemes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        packages.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return XcodeProjectParseResult(
            found: true,
            targets: targets,
            schemes: schemes,
            configurations: configurationNames.sorted(),
            packages: packages
        )
    }

    nonisolated private static func productTypeLabel(_ raw: String) -> String {
        switch raw {
        case "com.apple.product-type.application": return "App"
        case "com.apple.product-type.framework": return "Framework"
        case "com.apple.product-type.bundle": return "Bundle"
        case "com.apple.product-type.tool": return "Command Line Tool"
        case "com.apple.product-type.app-extension": return "App Extension"
        case "com.apple.product-type.ui-test-bundle": return "UI Test Bundle"
        case "com.apple.product-type.unit-test-bundle": return "Unit Test Bundle"
        case "com.apple.product-type.library.static": return "Static Library"
        case "com.apple.product-type.library.dynamic": return "Dynamic Library"
        case "com.apple.product-type.xpc-service": return "XPC Service"
        case "com.apple.product-type.application.watchapp", "com.apple.product-type.application.watchapp2": return "watchOS App"
        default:
            guard !raw.isEmpty else { return "Target" }
            return raw.components(separatedBy: ".").last?.capitalized ?? raw
        }
    }

    nonisolated private static func plistScalarString(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let array = value as? [Any] { return array.map { plistScalarString($0) }.joined(separator: " ") }
        if let dict = value as? [String: Any] {
            return dict.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }
        return String(describing: value)
    }

    private func calculateHealthAndRecommendations() {
        var score = 100
        var recs: [String] = []

        // Average file size check
        if averageFileSize > 1024 * 1024 { // > 1MB
            score -= 10
            recs.append("Average file size is extremely high. Consider compressing high-resolution assets or modularizing binary contents.")
        }

        // Extremely long files checks
        let longFiles = longestSwiftFiles.filter { $0.lineCount > 1000 }
        if !longFiles.isEmpty {
            score -= min(15, longFiles.count * 3)
            recs.append("Detected \(longFiles.count) Swift files with over 1,000 lines (longest: \(longFiles.first?.name ?? "")). Splitting these long source files will improve compile-time performance.")
        }

        // Concurrency usage
        if actorUsageCount == 0 && totalSwiftFiles > 50 {
            score -= 5
            recs.append("No Actors detected in a project with \(totalSwiftFiles) Swift files. Consider utilizing actors to protect shared mutable state in concurrent flows.")
        }

        // Modern observation usage
        if observationUsageCount == 0 && swiftUIUsageCount > 10 {
            score -= 5
            recs.append("Your SwiftUI project doesn't use the Swift 5.9+ `@Observable` macro. Move away from legacy Combine ObservableObjects to prevent redundant UI layout updates.")
        }

        // Localization
        if localizationCount == 0 {
            score -= 8
            recs.append("No localization keys/catalogs found. Add localized strings or `.xcstrings` to expand international user support.")
        }

        // Large files check
        let hugeFiles = largestFiles.filter { $0.size > 5 * 1024 * 1024 } // > 5MB
        if !hugeFiles.isEmpty {
            score -= min(10, hugeFiles.count * 2)
            recs.append("Found \(hugeFiles.count) files larger than 5MB on disk. Verify if they should be excluded from Git via `.gitignore` or tracked via LFS.")
        }

        // Package and dependencies check
        if packageCount > 10 {
            recs.append("High number of Swift packages detected (\(packageCount)). Regularly audit dependencies to avoid duplicate library link mismatches.")
        }

        if recs.isEmpty {
            recs.append("Outstanding code composition! Keep maintaining modular components and leveraging modern Swift 6 paradigms.")
        }

        if !xcodeProjectFound {
            recs.append("No .xcodeproj was found at the project root, so target, scheme, and signing details are unavailable in the Project tab.")
        }

        self.projectHealthScore = max(30, score)
        self.aiRecommendations = recs
    }

    // MARK: - Cache Persistence
    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.projectscanner.cache"),
           let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
            self.fileCache = decoded
        }
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(fileCache) {
            UserDefaults.standard.set(data, forKey: "com.swiftcode.projectscanner.cache")
        }
    }
}
