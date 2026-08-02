import Foundation
import Observation
import os.log

// MARK: - Structured Strongly Typed Swift Models

public enum BuildConfiguration: String, CaseIterable, Sendable, Codable {
    case debug = "Debug"
    case release = "Release"
}

public struct XcodeProject: Sendable, Codable, Hashable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let schemes: [SchemeMetadata]

    public init(url: URL, name: String, schemes: [SchemeMetadata]) {
        self.url = url
        self.name = name
        self.schemes = schemes
    }
}

public struct Workspace: Sendable, Codable, Hashable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let projects: [XcodeProject]

    public init(url: URL, name: String, projects: [XcodeProject]) {
        self.url = url
        self.name = name
        self.projects = projects
    }
}

public struct BuildDestination: Sendable, Codable, Hashable {
    public let destination: String

    public init(destination: String) {
        self.destination = destination
    }
}

public struct BuildDiagnostics: Sendable, Codable, Identifiable {
    public var id: UUID { UUID() }
    public let message: String
    public let severity: Severity
    public let filePath: String?
    public let line: Int?
    public let column: Int?

    public enum Severity: String, Sendable, Codable {
        case error
        case warning
        case note
    }

    public init(message: String, severity: Severity, filePath: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.message = message
        self.severity = severity
        self.filePath = filePath
        self.line = line
        self.column = column
    }
}

public struct BuildLogs: Sendable, Codable {
    public let lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }
}

public struct BuildResult: Sendable, Codable {
    public let status: BuildStatus
    public let appBundleURL: URL?
    public let diagnostics: [BuildDiagnostics]
    public let logs: BuildLogs

    public enum BuildStatus: String, Sendable, Codable {
        case succeeded
        case failed
        case cancelled
    }

    public init(status: BuildStatus, appBundleURL: URL?, diagnostics: [BuildDiagnostics], logs: BuildLogs) {
        self.status = status
        self.appBundleURL = appBundleURL
        self.diagnostics = diagnostics
        self.logs = logs
    }
}

public struct ProjectMetadata: Sendable, Codable {
    public let name: String
    public let productType: String
    public let targetName: String
    public let path: URL

    public init(name: String, productType: String, targetName: String, path: URL) {
        self.name = name
        self.productType = productType
        self.targetName = targetName
        self.path = path
    }
}

public struct BundleMetadata: Sendable, Codable {
    public let bundleIdentifier: String
    public let productName: String

    public init(bundleIdentifier: String, productName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.productName = productName
    }
}

public struct SchemeMetadata: Sendable, Codable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct GenerationResult: Sendable, Codable {
    public let success: Bool
    public let generatedProjectPath: URL?
    public let errorDescription: String?

    public init(success: Bool, generatedProjectPath: URL?, errorDescription: String?) {
        self.success = success
        self.generatedProjectPath = generatedProjectPath
        self.errorDescription = errorDescription
    }
}

public struct EnvironmentValidation: Sendable, Codable {
    public let xcodeAvailable: Bool
    public let xcodeSelectPath: String
    public let activeToolchain: String
    public let isValid: Bool
    public let errorDescription: String?

    public init(xcodeAvailable: Bool, xcodeSelectPath: String, activeToolchain: String, isValid: Bool, errorDescription: String?) {
        self.xcodeAvailable = xcodeAvailable
        self.xcodeSelectPath = xcodeSelectPath
        self.activeToolchain = activeToolchain
        self.isValid = isValid
        self.errorDescription = errorDescription
    }
}

// MARK: - Centralized XcodeBuildAPI

@Observable
@MainActor
public final class XcodeBuildAPI: Sendable {
    public static let shared = XcodeBuildAPI()

    private let logger = Logger(subsystem: "com.swiftcode.Build", category: "XcodeBuildAPI")

    // Shared State & Configurations
    public private(set) var currentLogs: [String] = []
    public private(set) var isExecuting = false
    public private(set) var currentStage = ""

    private init() {}

    // MARK: - Project Discovery

    /// Automatically performs project discovery using the specific ordering.
    /// 1. Current Workspace
    /// 2. Current Project
    /// 3. Current Editor
    /// 4. Current Folder
    /// 5. Parent Directory
    /// 6. Entire Workspace
    public func discoverActiveProject() -> XcodeProject? {
        logger.info("Starting project discovery...")

        let fm = FileManager.default
        var searchPaths: [URL] = []

        // 1. Current Workspace (DocumentCoordinator projectURL)
        if let workspaceURL = DocumentCoordinator.shared.projectURL {
            searchPaths.append(workspaceURL)
        }

        // 2. Current Project (ProjectSessionStore activeProject directoryURL)
        if let projectURL = ProjectSessionStore.shared.activeProject?.directoryURL {
            searchPaths.append(projectURL)
        }

        // 3. Current Editor (DocumentCoordinator activeDocument URL directory)
        if let editorURL = DocumentCoordinator.shared.activeDocument?.url {
            searchPaths.append(editorURL.deletingLastPathComponent())
            // Also trace ancestors
            if let ancestor = findWorkspaceAncestor(of: editorURL) {
                searchPaths.append(ancestor)
            }
        }

        // 4. Current Folder
        let currentFolder = URL(fileURLWithPath: fm.currentDirectoryPath)
        searchPaths.append(currentFolder)

        // 5. Parent Directory of Current Folder
        searchPaths.append(currentFolder.deletingLastPathComponent())

        // 6. Entire Workspace (Root of projects directory)
        searchPaths.append(CodingManager.shared.projectsRoot)

        // Deduplicate search paths while preserving order
        var uniquePaths: [URL] = []
        for path in searchPaths {
            let canonical = path.standardizedFileURL
            if !uniquePaths.contains(canonical) {
                uniquePaths.append(canonical)
            }
        }

        for path in uniquePaths {
            logger.info("Searching path: \(path.path)")
            if let project = scanDirectoryForProject(at: path) {
                logger.info("Discovered project: \(project.name) at \(project.url.path)")
                return project
            }
        }

        logger.warning("No supported project discovered.")
        return nil
    }

    private func scanDirectoryForProject(at url: URL) -> XcodeProject? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }

        do {
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

            // Look for .xcworkspace
            if let workspaceURL = contents.first(where: { $0.pathExtension == "xcworkspace" }) {
                // Discover schemes inside
                let schemes = discoverSchemes(at: workspaceURL)
                return XcodeProject(url: workspaceURL, name: workspaceURL.deletingPathExtension().lastPathComponent, schemes: schemes)
            }

            // Look for .xcodeproj
            if let xcodeprojURL = contents.first(where: { $0.pathExtension == "xcodeproj" }) {
                let schemes = discoverSchemes(at: xcodeprojURL)
                return XcodeProject(url: xcodeprojURL, name: xcodeprojURL.deletingPathExtension().lastPathComponent, schemes: schemes)
            }

            // Look for Package.swift
            if let packageURL = contents.first(where: { $0.lastPathComponent == "Package.swift" }) {
                // For Package.swift, scheme is usually same as name of the directory
                let schemeName = url.lastPathComponent
                return XcodeProject(url: packageURL, name: schemeName, schemes: [SchemeMetadata(name: schemeName)])
            }

        } catch {
            logger.error("Failed to read directory \(url.path): \(error.localizedDescription)")
        }

        return nil
    }

    private func findWorkspaceAncestor(of url: URL) -> URL? {
        let fm = FileManager.default
        var current = url.deletingLastPathComponent()
        while current.path != "/" {
            let packageSwift = current.appendingPathComponent("Package.swift")
            if fm.fileExists(atPath: packageSwift.path) {
                return current
            }
            if let contents = try? fm.contentsOfDirectory(at: current, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                if contents.contains(where: { $0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace" }) {
                    return current
                }
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private func discoverSchemes(at url: URL) -> [SchemeMetadata] {
        let fm = FileManager.default
        var schemes = Set<String>()

        // Scan for xcshareddata/xcschemes or xcschemes
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "xcscheme" {
                    schemes.insert(fileURL.deletingPathExtension().lastPathComponent)
                }
            }
        }

        if schemes.isEmpty {
            schemes.insert(url.deletingPathExtension().lastPathComponent)
        }

        return schemes.sorted().map { SchemeMetadata(name: $0) }
    }

    // MARK: - Active Project Configuration Discovery

    public func determineActiveWorkspace() -> Workspace? {
        guard let proj = discoverActiveProject() else { return nil }
        if proj.url.pathExtension == "xcworkspace" {
            return Workspace(url: proj.url, name: proj.name, projects: [proj])
        }
        return nil
    }

    public func determineActiveProject() -> XcodeProject? {
        return discoverActiveProject()
    }

    public func determineActiveScheme() -> SchemeMetadata? {
        if let selected = XcodeBuildManager.shared.selectedScheme {
            return SchemeMetadata(name: selected)
        }
        return discoverActiveProject()?.schemes.first
    }

    public func determineActiveBuildConfiguration() -> BuildConfiguration {
        if XcodeBuildManager.shared.selectedConfiguration == "Release" {
            return .release
        }
        return .debug
    }

    public func determineProductName() -> String {
        return determineActiveProject()?.name ?? "SwiftCodeDemo"
    }

    public func determineBundleIdentifier() -> String {
        let pName = determineProductName().lowercased().replacingOccurrences(of: " ", with: "")
        if let project = ProjectSessionStore.shared.activeProject,
           let ciConfig = project.ciBuildConfiguration, !ciConfig.bundleIdentifier.isEmpty {
            return ciConfig.bundleIdentifier
        }
        return "com.example.\(pName)"
    }

    public func determineBuildDestination() -> BuildDestination {
        return BuildDestination(destination: XcodeBuildManager.shared.selectedDestination)
    }

    public func determineDerivedDataLocation() -> URL {
        if let proj = discoverActiveProject() {
            return proj.url.deletingLastPathComponent().appendingPathComponent("build/DerivedData")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SwiftCode/DerivedData")
    }

    public func determineAppBundleURL() -> URL? {
        guard let proj = discoverActiveProject() else { return nil }
        let rootDir = proj.url.deletingLastPathComponent()
        let productsURL = rootDir.appendingPathComponent("build/DerivedData/Build/Products")
        let fm = FileManager.default

        if fm.fileExists(atPath: productsURL.path) {
            do {
                let folders = try fm.contentsOfDirectory(at: productsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                for folder in folders {
                    let items = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                    if let appFile = items.first(where: { $0.pathExtension == "app" }) {
                        return appFile
                    }
                }
            } catch {
                logger.error("Error walking build products: \(error.localizedDescription)")
            }
        }

        // Fallback to managed sandbox builds folder
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let buildsDir = appSupport.appendingPathComponent("SwiftCode/Builds/\(proj.name)")
        if let items = try? fm.contentsOfDirectory(at: buildsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            if let appFile = items.first(where: { $0.pathExtension == "app" }) {
                return appFile
            }
        }

        return nil
    }

    public func determineProjectMetadata() -> ProjectMetadata? {
        guard let proj = discoverActiveProject() else { return nil }
        return ProjectMetadata(
            name: proj.name,
            productType: "com.apple.product-type.application",
            targetName: proj.name,
            path: proj.url
        )
    }

    // MARK: - Validation & Environment

    public func validateBuildEnvironment() async -> EnvironmentValidation {
        currentStage = "Validating build environment..."
        let fm = FileManager.default
        let xcodePath = XcodeBuildManager.shared.getXcodeBuildPath()
        let xcodeAvailable = fm.fileExists(atPath: xcodePath) && fm.isExecutableFile(atPath: xcodePath)

        var selectPath = "/usr/bin/xcode-select"
        if !fm.fileExists(atPath: selectPath) {
            selectPath = "N/A"
        }

        let activeToolchain = await XcodeBuildManager.shared.getActiveToolchain()
        let isValid = xcodeAvailable && selectPath != "N/A"

        return EnvironmentValidation(
            xcodeAvailable: xcodeAvailable,
            xcodeSelectPath: selectPath,
            activeToolchain: activeToolchain,
            isValid: isValid,
            errorDescription: isValid ? nil : "xcodebuild tool was not found or is not executable at: \(xcodePath)"
        )
    }

    // MARK: - Project Generation (Tuist / Fallback)

    /// Generates an Xcode project using Tuist or falls back to Package.swift/SPM or template generation.
    public func generateProject(projectName: String, scheme: String, bundleIdentifier: String, targetURL: URL) async -> GenerationResult {
        isExecuting = true
        currentStage = "Generating Xcode Project..."
        currentLogs.removeAll()
        appendLog("[SYSTEM] Starting project generation for '\(projectName)' at \(targetURL.path)")

        let fm = FileManager.default

        // Ensure the directory exists
        if !fm.fileExists(atPath: targetURL.path) {
            try? fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
        }

        // 1. Check if Tuist is available to generate
        let tuistPaths = ["/usr/local/bin/tuist", "/opt/homebrew/bin/tuist", "/usr/bin/tuist"]
        var resolvedTuist: String? = nil
        for path in tuistPaths {
            if fm.fileExists(atPath: path) && fm.isExecutableFile(atPath: path) {
                resolvedTuist = path
                break
            }
        }

        if let tuistPath = resolvedTuist {
            appendLog("[SYSTEM] Discovered Tuist at \(tuistPath). Creating Project.swift config...")

            // Generate Project.swift
            let projectSwiftContent = """
import ProjectDescription

let project = Project(
    name: "\(projectName)",
    targets: [
        .target(
            name: "\(projectName)",
            destinations: .iOS,
            product: .app,
            bundleId: "\(bundleIdentifier)",
            infoPlist: .default,
            sources: ["Sources/**"],
            resources: ["Resources/**"]
        )
    ]
)
"""
            let projectSwiftURL = targetURL.appendingPathComponent("Project.swift")
            try? projectSwiftContent.write(to: projectSwiftURL, atomically: true, encoding: .utf8)

            // Generate basic directories if not existing
            let sourcesDir = targetURL.appendingPathComponent("Sources")
            try? fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

            let mainSwift = sourcesDir.appendingPathComponent("main.swift")
            if !fm.fileExists(atPath: mainSwift.path) {
                let templateMain = """
import SwiftUI

@main
struct AppEntry: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Hello, SwiftCode!")
            .padding()
    }
}
"""
                try? templateMain.write(to: mainSwift, atomically: true, encoding: .utf8)
            }

            appendLog("[SYSTEM] Running 'tuist generate'...")
            do {
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: URL(fileURLWithPath: tuistPath),
                    arguments: ["generate"],
                    workingDirectory: targetURL
                )

                appendLog(result.stdout)
                if !result.stderr.isEmpty {
                    appendLog("[ERROR] " + result.stderr)
                }

                if result.exitCode == 0 {
                    let generatedProj = targetURL.appendingPathComponent("\(projectName).xcodeproj")
                    isExecuting = false
                    return GenerationResult(success: true, generatedProjectPath: generatedProj, errorDescription: nil)
                } else {
                    appendLog("[WARNING] Tuist generation failed. Falling back to Package.swift SPM generation...")
                }
            } catch {
                appendLog("[WARNING] Tuist failed to launch: \(error.localizedDescription). Falling back to SPM...")
            }
        }

        // 2. Fallback: Generate standard SPM Package.swift & optionally use swift package generate-xcodeproj (if available)
        appendLog("[SYSTEM] Generating SPM Package.swift manifest...")
        let packageSwiftContent = """
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "\(projectName)",
    platforms: [
        .macOS(.v15),
        .iOS(.v16)
    ],
    products: [
        .executable(name: "\(projectName)", targets: ["\(projectName)"])
    ],
    targets: [
        .executableTarget(
            name: "\(projectName)",
            path: "Sources"
        )
    ]
)
"""
        let packageSwiftURL = targetURL.appendingPathComponent("Package.swift")
        try? packageSwiftContent.write(to: packageSwiftURL, atomically: true, encoding: .utf8)

        let sourcesDir = targetURL.appendingPathComponent("Sources")
        try? fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let mainSwift = sourcesDir.appendingPathComponent("main.swift")
        if !fm.fileExists(atPath: mainSwift.path) {
            let templateMain = """
import SwiftUI

@main
struct AppEntry: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello, SwiftCode!")
                .padding()
        }
    }
}
"""
            try? templateMain.write(to: mainSwift, atomically: true, encoding: .utf8)
        }

        // Run generate-xcodeproj if swift toolchain is present
        let swiftPath = "/usr/bin/swift"
        if fm.fileExists(atPath: swiftPath) {
            appendLog("[SYSTEM] Invoking 'swift package generate-xcodeproj'...")
            do {
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: URL(fileURLWithPath: swiftPath),
                    arguments: ["package", "generate-xcodeproj"],
                    workingDirectory: targetURL
                )
                appendLog(result.stdout)
                if result.exitCode == 0 {
                    let generatedProj = targetURL.appendingPathComponent("\(projectName).xcodeproj")
                    isExecuting = false
                    return GenerationResult(success: true, generatedProjectPath: generatedProj, errorDescription: nil)
                }
            } catch {
                appendLog("[WARNING] SPM generate-xcodeproj failed: \(error.localizedDescription)")
            }
        }

        // If xcodeproj generation fails but Package.swift is written successfully, return Package.swift as project URL
        isExecuting = false
        appendLog("[SYSTEM] Setup completed with Package.swift.")
        return GenerationResult(success: true, generatedProjectPath: packageSwiftURL, errorDescription: nil)
    }

    // MARK: - Build Execution

    public func buildProject() async -> BuildResult {
        guard !isExecuting else {
            return BuildResult(status: .cancelled, appBundleURL: nil, diagnostics: [], logs: BuildLogs(lines: ["Build already in progress."]))
        }

        isExecuting = true
        currentStage = "Building Project..."
        currentLogs.removeAll()

        guard let project = discoverActiveProject() else {
            isExecuting = false
            return BuildResult(
                status: .failed,
                appBundleURL: nil,
                diagnostics: [BuildDiagnostics(message: "No supported Xcode project or Package.swift found to build.", severity: .error)],
                logs: BuildLogs(lines: ["Build failed: No project found."])
            )
        }

        appendLog("[SYSTEM] Initiating build for \(project.name) via XcodeBuildAPI...")

        // Update selection in managers to ensure synchronization
        XcodeBuildManager.shared.discoverSchemes(at: project.url)
        let activeScheme = determineActiveScheme()?.name ?? project.name

        // Run build using XcodeBuildManager to share real-time state and UI hooks
        await XcodeBuildManager.shared.runBuild(
            projectURL: project.url.deletingLastPathComponent(),
            scheme: activeScheme,
            configuration: determineActiveBuildConfiguration().rawValue,
            destination: determineBuildDestination().destination
        )

        // Stream the logs from BuildManager to our current logs for consistency
        self.currentLogs = XcodeBuildManager.shared.buildLogs

        let status = XcodeBuildManager.shared.currentStatus
        isExecuting = false

        var buildStatus: BuildResult.BuildStatus = .failed
        if status == .succeeded {
            buildStatus = .succeeded
        } else if status == .cancelled {
            buildStatus = .cancelled
        }

        // Parse basic diagnostics
        var diagnostics: [BuildDiagnostics] = []
        for log in currentLogs {
            if log.lowercased().contains("error:") {
                diagnostics.append(BuildDiagnostics(message: log, severity: .error))
            } else if log.lowercased().contains("warning:") {
                diagnostics.append(BuildDiagnostics(message: log, severity: .warning))
            }
        }

        return BuildResult(
            status: buildStatus,
            appBundleURL: determineAppBundleURL(),
            diagnostics: diagnostics,
            logs: BuildLogs(lines: currentLogs)
        )
    }

    // MARK: - Clean Execution

    public func cleanProject() async -> Bool {
        guard !isExecuting else { return false }
        isExecuting = true
        currentStage = "Cleaning build artifacts..."
        currentLogs.removeAll()

        guard let project = discoverActiveProject() else {
            isExecuting = false
            return false
        }

        appendLog("[SYSTEM] Cleaning project: \(project.name)")

        let xcodebuild = XcodeBuildManager.shared.getXcodeBuildPath()
        let derivedData = determineDerivedDataLocation()

        // 1. Delete DerivedData folder
        let fm = FileManager.default
        if fm.fileExists(atPath: derivedData.path) {
            do {
                try fm.removeItem(at: derivedData)
                appendLog("[SYSTEM] Removed DerivedData directory: \(derivedData.path)")
            } catch {
                appendLog("[ERROR] Failed to delete DerivedData: \(error.localizedDescription)")
            }
        }

        // 2. Execute xcodebuild clean
        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: xcodebuild),
                arguments: [
                    "-project", project.url.path,
                    "-scheme", determineActiveScheme()?.name ?? project.name,
                    "clean"
                ],
                workingDirectory: project.url.deletingLastPathComponent()
            )
            appendLog(result.stdout)
            if !result.stderr.isEmpty {
                appendLog("[ERROR] " + result.stderr)
            }
            isExecuting = false
            return result.exitCode == 0
        } catch {
            appendLog("[ERROR] Clean failed: \(error.localizedDescription)")
            isExecuting = false
            return false
        }
    }

    // MARK: - Cancel Execution

    public func cancelBuild() {
        XcodeBuildManager.shared.cancelBuild()
        isExecuting = false
        currentStage = "Cancelled"
    }

    // MARK: - Logging helpers

    private func appendLog(_ log: String) {
        currentLogs.append(log)
        logger.info("\(log)")
    }
}
