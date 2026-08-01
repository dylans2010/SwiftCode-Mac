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
                actorUsageCount: 0, recentChanges: [], newCache: cache
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
            newCache: localCache
        )
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
