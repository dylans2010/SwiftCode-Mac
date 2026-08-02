import Foundation
import Observation
import os.log

/// Strongly typed metadata model representing a fully resolved workspace/project structure
public struct ResolvedProjectMetadata: Sendable, Hashable {
    public let rootURL: URL
    public let projectName: String
    public let isSwiftPackage: Bool
    public let isXcodeProject: Bool
    public let isXcodeWorkspace: Bool
    public let packageSwiftURL: URL?
    public let xcodeprojURL: URL?
    public let xcworkspaceURL: URL?
    public let buildRootURL: URL
    public let buildDestination: String
}

/// Error types that can be encountered during project resolution
public enum ProjectResolutionError: Error, LocalizedError, Sendable {
    case activeProjectNotFound
    case resolutionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .activeProjectNotFound:
            return "No active workspace project was detected or linked."
        case .resolutionFailed(let reason):
            return "Failed to resolve project details: \(reason)"
        }
    }
}

/// Centralized, reusable project resolution service to detect and parse active workspace state
@Observable
@MainActor
public final class ProjectResolver: Sendable {
    public static let shared = ProjectResolver()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "ProjectResolver")

    private init() {}

    /// Automatically discovers and resolves the current project metadata from the active session or open files.
    /// Never relies on hardcoded or placeholder values, and never requires manual selection if a workspace is already open.
    public func resolveActiveProject() throws -> ResolvedProjectMetadata {
        let fm = FileManager.default

        // 1. Locate root URL through various active pathways
        var potentialRootURL: URL? = nil

        if let activeProject = ProjectSessionStore.shared.activeProject {
            potentialRootURL = activeProject.directoryURL
            logger.info("Located active project from session store: \(activeProject.name)")
        } else if let coordProjURL = DocumentCoordinator.shared.projectURL {
            potentialRootURL = coordProjURL
            logger.info("Located active project from coordinator project URL: \(coordProjURL.path)")
        } else if let activeDocURL = DocumentCoordinator.shared.activeDocument?.url {
            // Find parent directory containing workspace markers (Package.swift, .xcodeproj, .xcworkspace, project.json)
            potentialRootURL = findWorkspaceAncestor(of: activeDocURL)
            if let root = potentialRootURL {
                logger.info("Resolved project root by tracing active document ancestor: \(root.path)")
            }
        }

        // 2. Validate we discovered a directory
        guard let rootURL = potentialRootURL else {
            throw ProjectResolutionError.activeProjectNotFound
        }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProjectResolutionError.resolutionFailed("Resolved path '\(rootURL.path)' does not exist or is not a folder.")
        }

        // 3. Scan root files to identify format capabilities
        let projectName = rootURL.lastPathComponent
        let packageSwiftURL = rootURL.appendingPathComponent("Package.swift")
        let isSwiftPackage = fm.fileExists(atPath: packageSwiftURL.path)

        var xcodeprojURL: URL? = nil
        var xcworkspaceURL: URL? = nil

        do {
            let files = try fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            xcodeprojURL = files.first { $0.pathExtension == "xcodeproj" }
            xcworkspaceURL = files.first { $0.pathExtension == "xcworkspace" }
        } catch {
            logger.warning("Failed to list files under resolved root URL: \(error.localizedDescription)")
        }

        let isXcodeProject = xcodeprojURL != nil
        let isXcodeWorkspace = xcworkspaceURL != nil

        // 4. Determine build destination and root variables
        let buildRootURL = rootURL.appendingPathComponent("build")
        let buildDestination = XcodeBuildManager.shared.selectedDestination

        let metadata = ResolvedProjectMetadata(
            rootURL: rootURL,
            projectName: projectName,
            isSwiftPackage: isSwiftPackage,
            isXcodeProject: isXcodeProject,
            isXcodeWorkspace: isXcodeWorkspace,
            packageSwiftURL: isSwiftPackage ? packageSwiftURL : nil,
            xcodeprojURL: xcodeprojURL,
            xcworkspaceURL: xcworkspaceURL,
            buildRootURL: buildRootURL,
            buildDestination: buildDestination
        )

        // Keep DocumentCoordinator synchronized
        DocumentCoordinator.shared.projectURL = rootURL

        return metadata
    }

    /// Recursively traces directories up to find active Package.swift or Xcode project files
    private func findWorkspaceAncestor(of url: URL) -> URL? {
        let fm = FileManager.default
        var currentURL = url.deletingLastPathComponent()

        while currentURL.path != "/" {
            let packageSwift = currentURL.appendingPathComponent("Package.swift")
            let projectJson = currentURL.appendingPathComponent("project.json")

            if fm.fileExists(atPath: packageSwift.path) || fm.fileExists(atPath: projectJson.path) {
                return currentURL
            }

            if let contents = try? fm.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                if contents.contains(where: { $0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace" }) {
                    return currentURL
                }
            }

            currentURL = currentURL.deletingLastPathComponent()
        }

        return nil
    }
}
