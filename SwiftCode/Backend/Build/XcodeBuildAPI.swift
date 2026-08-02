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

public struct XcodeProjectMetadata: Sendable, Codable {
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

// MARK: - XcodeGen Strongly Typed Installation State

public enum XcodeGenInstallationState: String, Sendable, Codable {
    case installed
    case missing
    case installing
    case failed
}

// MARK: - Independent Project Generation Error

public struct ProjectGenerationError: Identifiable, Sendable, Codable {
    public var id: UUID { UUID() }
    public let stage: String
    public let timestamp: Date
    public let message: String
    public let suggestedRecovery: String?

    public init(stage: String, timestamp: Date = Date(), message: String, suggestedRecovery: String? = nil) {
        self.stage = stage
        self.timestamp = timestamp
        self.message = message
        self.suggestedRecovery = suggestedRecovery
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

    // XcodeGen Integration Properties
    public var showProjectGenerationUI = false
    public private(set) var xcodegenState: XcodeGenInstallationState = .missing
    public private(set) var installationStatusString = ""
    public private(set) var activeGenerationError: ProjectGenerationError? = nil

    @ObservationIgnored
    private var generationContinuation: CheckedContinuation<Bool, Never>?

    private init() {}

    // MARK: - Project Discovery & Existence Check

    /// Checks if a valid .xcodeproj or .xcworkspace is present anywhere in our resolved path hierarchy.
    public func hasWorkspaceOrXcodeproj() -> Bool {
        logStage("Checking for existing project")
        let fm = FileManager.default
        let root = resolveProjectRoot()

        do {
            let contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let hasFiles = contents.contains { $0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace" }
            if hasFiles {
                appendLog("[SYSTEM] Located existing Xcode workspace/project file.")
                return true
            }
        } catch {
            appendLog("[WARNING] Directory scanning failed: \(error.localizedDescription)")
        }
        return false
    }

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

    // MARK: - Auto-resolved Path Configurations

    public func resolveProjectRoot() -> URL {
        if let workspaceURL = DocumentCoordinator.shared.projectURL {
            return workspaceURL
        }
        if let projectURL = ProjectSessionStore.shared.activeProject?.directoryURL {
            return projectURL
        }
        if let editorURL = DocumentCoordinator.shared.activeDocument?.url {
            return editorURL.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    public func resolveSourceDirectory() -> String {
        let root = resolveProjectRoot()
        let fm = FileManager.default
        let commonDirs = ["Sources", "Views", "Features", "Components"]
        for dir in commonDirs {
            let dirURL = root.appendingPathComponent(dir)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
        }
        return "Sources" // default fallback
    }

    public func resolveResourcesDirectory() -> String? {
        let root = resolveProjectRoot()
        let fm = FileManager.default
        let resourcesURL = root.appendingPathComponent("Resources")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: resourcesURL.path, isDirectory: &isDir), isDir.boolValue {
            return "Resources"
        }
        return nil
    }

    public func resolveOutputLocation() -> URL {
        return resolveProjectRoot().appendingPathComponent("build")
    }

    public func resolveBuildDirectory() -> URL {
        return resolveOutputLocation()
    }

    public func resolveDerivedDataLocation() -> URL {
        return resolveProjectRoot().appendingPathComponent("build/DerivedData")
    }

    public func resolveWorkingDirectory() -> URL {
        return resolveProjectRoot()
    }

    public func resolveTargetPaths() -> [String] {
        var paths = [resolveSourceDirectory()]
        if let res = resolveResourcesDirectory() {
            paths.append(res)
        }
        return paths
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

    public func determineProjectMetadata() -> XcodeProjectMetadata? {
        guard let proj = discoverActiveProject() else { return nil }
        return XcodeProjectMetadata(
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

    // MARK: - XcodeGen Detection & Installation

    public func checkXcodeGenInstallation() async -> XcodeGenInstallationState {
        logStage("Checking XcodeGen")
        let fm = FileManager.default
        let possiblePaths = [
            "/opt/homebrew/bin/xcodegen",
            "/usr/local/bin/xcodegen",
            "/usr/bin/xcodegen"
        ]

        for path in possiblePaths {
            if fm.fileExists(atPath: path) && fm.isExecutableFile(atPath: path) {
                xcodegenState = .installed
                appendLog("[SYSTEM] Discovered XcodeGen executable at: \(path)")
                return .installed
            }
        }

        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/which"),
                arguments: ["xcodegen"]
            )
            if result.exitCode == 0 {
                xcodegenState = .installed
                appendLog("[SYSTEM] Located XcodeGen in system PATH.")
                return .installed
            }
        } catch {}

        xcodegenState = .missing
        appendLog("[SYSTEM] XcodeGen is not installed or not in PATH.")
        return .missing
    }

    public func checkHomebrewInstallation() -> Bool {
        logStage("Checking Homebrew")
        let fm = FileManager.default
        let possiblePaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            "/usr/bin/brew"
        ]
        for path in possiblePaths {
            if fm.fileExists(atPath: path) {
                appendLog("[SYSTEM] Discovered Homebrew executable at: \(path)")
                return true
            }
        }
        appendLog("[SYSTEM] Homebrew is not installed on this system.")
        return false
    }

    private func getHomebrewPath() -> String? {
        let fm = FileManager.default
        let possiblePaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            "/usr/bin/brew"
        ]
        for path in possiblePaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    public func installXcodeGen() async -> Bool {
        logStage("Installing XcodeGen")
        activeGenerationError = nil

        guard checkHomebrewInstallation() else {
            xcodegenState = .failed
            installationStatusString = "Homebrew is missing. Please install Homebrew first."
            activeGenerationError = ProjectGenerationError(
                stage: "Checking Homebrew",
                message: "Homebrew was not found on this system.",
                suggestedRecovery: "Please install Homebrew (https://brew.sh) and try again."
            )
            appendLog("[ERROR] Homebrew is not installed. XcodeGen installation requires Homebrew.")
            return false
        }

        guard let brewPath = getHomebrewPath() else { return false }

        xcodegenState = .installing
        installationStatusString = "Preparing installation..."
        appendLog("[SYSTEM] Preparing installation...")

        installationStatusString = "Downloading..."
        appendLog("[SYSTEM] Downloading XcodeGen...")

        installationStatusString = "Installing..."
        appendLog("[SYSTEM] Installing XcodeGen via Homebrew...")

        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: brewPath),
                arguments: ["install", "xcodegen"]
            )
            appendLog(result.stdout)
            if !result.stderr.isEmpty {
                appendLog("[ERROR] " + result.stderr)
            }

            installationStatusString = "Verifying installation..."
            appendLog("[SYSTEM] Verifying installation...")
            let verified = await checkXcodeGenInstallation()
            if verified == .installed {
                installationStatusString = "Installation complete"
                appendLog("[SYSTEM] Installation complete!")
                xcodegenState = .installed
                return true
            } else {
                installationStatusString = "Verification failed"
                activeGenerationError = ProjectGenerationError(
                    stage: "Installing XcodeGen",
                    message: "XcodeGen verification failed post-installation.",
                    suggestedRecovery: "Check Homebrew logs or manually run 'brew install xcodegen' in the terminal."
                )
                appendLog("[ERROR] Verification failed. XcodeGen is still not found after installation.")
                xcodegenState = .failed
                return false
            }
        } catch {
            installationStatusString = "Installation failed"
            activeGenerationError = ProjectGenerationError(
                stage: "Installing XcodeGen",
                message: error.localizedDescription,
                suggestedRecovery: "Ensure your network is active and try clicking 'Install Component' again."
            )
            appendLog("[ERROR] Installation failed: \(error.localizedDescription)")
            xcodegenState = .failed
            return false
        }
    }

    // MARK: - Project Generation (XcodeGen)

    public func generateProjectWithXcodeGen(
        projectName: String,
        scheme: String,
        bundleIdentifier: String,
        organizationIdentifier: String = "com.example",
        deploymentTarget: String = "16.0",
        targetPlatform: String = "iOS"
    ) async -> Bool {
        activeGenerationError = nil

        logStage("Generating project.yml")
        let rootURL = resolveProjectRoot()
        let sourceDir = resolveSourceDirectory()

        let fm = FileManager.default
        let sourceURL = rootURL.appendingPathComponent(sourceDir)
        if !fm.fileExists(atPath: sourceURL.path) {
            do {
                try fm.createDirectory(at: sourceURL, withIntermediateDirectories: true)
                appendLog("[SYSTEM] Created source directory at \(sourceURL.path)")
            } catch {
                activeGenerationError = ProjectGenerationError(
                    stage: "Generating project.yml",
                    message: "Failed to create source folder: \(error.localizedDescription)",
                    suggestedRecovery: "Ensure proper filesystem permissions at \(rootURL.path)."
                )
                return false
            }
        }

        // Write main.swift template if missing
        let mainSwift = sourceURL.appendingPathComponent("main.swift")
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
            do {
                try templateMain.write(to: mainSwift, atomically: true, encoding: .utf8)
                appendLog("[SYSTEM] Created main.swift template file.")
            } catch {
                appendLog("[WARNING] Failed to write main.swift template: \(error.localizedDescription)")
            }
        }

        // Generate Info.plist if missing
        let infoPlistURL = rootURL.appendingPathComponent("Info.plist")
        if !fm.fileExists(atPath: infoPlistURL.path) {
            let plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>UILaunchScreen</key>
	<dict/>
</dict>
</plist>
"""
            try? plistContent.write(to: infoPlistURL, atomically: true, encoding: .utf8)
        }

        // Load project.yml template
        var templateContent = ""
        if let templateURL = Bundle.main.url(forResource: "project", withExtension: "yml"),
           let loaded = try? String(contentsOf: templateURL, encoding: .utf8) {
            templateContent = loaded
        } else {
            // Robust fallback template
            templateContent = """
name: __PROJECT_NAME__
options:
  bundleIdPrefix: __ORGANIZATION_IDENTIFIER__
settings:
  base:
    SWIFT_VERSION: 5.0
configs:
  Debug: debug
  Release: release
targets:
  __TARGET_NAME__:
    type: application
    platform: __TARGET_PLATFORM__
    deploymentTarget: "__DEPLOYMENT_TARGET__"
    sources:
__TARGET_SOURCES__
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: __BUNDLE_IDENTIFIER__
        INFOPLIST_FILE: Info.plist
schemes:
  __SCHEME_NAME__:
    build:
      targets:
        __TARGET_NAME__: all
"""
        }

        let targetPaths = resolveTargetPaths()
        let sourcesBlock = targetPaths.map { "      - \($0)" }.joined(separator: "\n")

        let finalYML = templateContent
            .replacingOccurrences(of: "__PROJECT_NAME__", with: projectName)
            .replacingOccurrences(of: "__SCHEME_NAME__", with: scheme)
            .replacingOccurrences(of: "__TARGET_NAME__", with: projectName)
            .replacingOccurrences(of: "__ORGANIZATION_IDENTIFIER__", with: organizationIdentifier)
            .replacingOccurrences(of: "__BUNDLE_IDENTIFIER__", with: bundleIdentifier)
            .replacingOccurrences(of: "__DEPLOYMENT_TARGET__", with: deploymentTarget)
            .replacingOccurrences(of: "__TARGET_PLATFORM__", with: targetPlatform)
            .replacingOccurrences(of: "__TARGET_SOURCES__", with: sourcesBlock)

        let projectYMLURL = rootURL.appendingPathComponent("project.yml")
        do {
            try finalYML.write(to: projectYMLURL, atomically: true, encoding: .utf8)
            appendLog("[SYSTEM] Generated project.yml at \(projectYMLURL.path)")
        } catch {
            activeGenerationError = ProjectGenerationError(
                stage: "Generating project.yml",
                message: "Failed to write project.yml: \(error.localizedDescription)",
                suggestedRecovery: "Ensure proper filesystem permissions in the project folder."
            )
            appendLog("[ERROR] Failed to write project.yml: \(error.localizedDescription)")
            return false
        }

        logStage("Generating Xcode project")
        let xcodegenPath: String
        let possiblePaths = [
            "/opt/homebrew/bin/xcodegen",
            "/usr/local/bin/xcodegen",
            "/usr/bin/xcodegen"
        ]
        var foundPath: String? = nil
        for path in possiblePaths {
            if fm.fileExists(atPath: path) && fm.isExecutableFile(atPath: path) {
                foundPath = path
                break
            }
        }

        xcodegenPath = foundPath ?? "xcodegen"
        appendLog("[SYSTEM] Executing XcodeGen generation stage...")

        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: xcodegenPath),
                arguments: ["generate"],
                workingDirectory: rootURL
            )
            appendLog(result.stdout)
            if !result.stderr.isEmpty {
                appendLog("[ERROR] " + result.stderr)
            }

            if result.exitCode == 0 {
                logStage("Validating generated project")
                let generatedProj = rootURL.appendingPathComponent("\(projectName).xcodeproj")
                if fm.fileExists(atPath: generatedProj.path) {
                    logStage("Moving project")
                    appendLog("[SYSTEM] Generated project \(projectName).xcodeproj is placed in the project root.")

                    logStage("Refreshing project metadata")
                    if let activeProj = ProjectSessionStore.shared.activeProject {
                        ProjectSessionStore.shared.refreshFileTree(for: activeProj)
                    }

                    appendLog("[SYSTEM] Validation succeeded!")
                    return true
                } else {
                    activeGenerationError = ProjectGenerationError(
                        stage: "Validating generated project",
                        message: "The generated .xcodeproj file could not be verified on disk.",
                        suggestedRecovery: "Ensure XcodeGen has write permission to \(rootURL.path)."
                    )
                    appendLog("[ERROR] Generated project file not found at expected location: \(generatedProj.path)")
                    return false
                }
            } else {
                activeGenerationError = ProjectGenerationError(
                    stage: "Generating Xcode project",
                    message: "XcodeGen completed with a non-zero exit code \(result.exitCode). Details: \(result.stderr)",
                    suggestedRecovery: "Please correct any formatting errors in project.yml."
                )
                appendLog("[ERROR] XcodeGen failed with exit code \(result.exitCode)")
                return false
            }
        } catch {
            activeGenerationError = ProjectGenerationError(
                stage: "Generating Xcode project",
                message: "Launch failure: \(error.localizedDescription)",
                suggestedRecovery: "Check that XcodeGen is fully functional in terminal."
            )
            appendLog("[ERROR] XcodeGen failed to launch: \(error.localizedDescription)")
            return false
        }
    }

    public func completeProjectGeneration(success: Bool) {
        showProjectGenerationUI = false
        if let continuation = generationContinuation {
            generationContinuation = nil
            continuation.resume(returning: success)
        }
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

        // 1. Check for existing project (.xcworkspace or .xcodeproj)
        let projectExists = hasWorkspaceOrXcodeproj()
        if !projectExists {
            appendLog("[SYSTEM] No existing .xcworkspace or .xcodeproj located. Transitioning to project generation workflow...")
            showProjectGenerationUI = true

            // Suspend until completed or cancelled
            let success = await withCheckedContinuation { continuation in
                self.generationContinuation = continuation
            }

            if !success {
                isExecuting = false
                appendLog("[ERROR] Project generation was cancelled or failed.")
                return BuildResult(
                    status: .failed,
                    appBundleURL: nil,
                    diagnostics: [BuildDiagnostics(message: "Project generation was cancelled or failed.", severity: .error)],
                    logs: BuildLogs(lines: ["Build failed: No project generated."])
                )
            }

            // Verify project now exists
            let verified = hasWorkspaceOrXcodeproj()
            if !verified {
                isExecuting = false
                appendLog("[ERROR] Generated project could not be resolved.")
                return BuildResult(
                    status: .failed,
                    appBundleURL: nil,
                    diagnostics: [BuildDiagnostics(message: "Verification failed after project generation.", severity: .error)],
                    logs: BuildLogs(lines: ["Build failed: Post-generation validation failed."])
                )
            }
        }

        logStage("Continuing build")
        appendLog("[SYSTEM] Initiating build via XcodeBuildAPI...")

        guard let project = discoverActiveProject() else {
            isExecuting = false
            return BuildResult(
                status: .failed,
                appBundleURL: nil,
                diagnostics: [BuildDiagnostics(message: "No supported Xcode project found to build.", severity: .error)],
                logs: BuildLogs(lines: ["Build failed: No project found."])
            )
        }

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

    private func logStage(_ stage: String) {
        currentStage = stage
        appendLog("[SYSTEM] Stage: \(stage)")
        UnifiedLogger.shared.log("Transitioned to stage: \(stage)", severity: .system, subsystem: "XcodeBuildAPI", operation: stage)
    }
}
