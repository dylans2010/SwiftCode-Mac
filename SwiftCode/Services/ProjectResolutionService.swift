import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Services", category: "ProjectResolution")

@Observable
@MainActor
public final class ProjectResolutionService: Sendable {
    public static let shared = ProjectResolutionService()

    /// The active project's cached Xcode projects parsed models
    public var parsedProjects: [URL: XcodeProjModel] = [:]

    /// Currently selected target ID
    public var selectedTargetID: String? {
        didSet {
            logger.info("Selected target changed to: \(self.selectedTargetID ?? "None", privacy: .public)")
        }
    }

    private init() {}

    /// Updates cached project models for the current active project path
    public func updateParsedProjects(with models: [URL: XcodeProjModel]) {
        self.parsedProjects = models
        if selectedTargetID == nil, let firstModel = models.values.first, let firstTarget = firstModel.targets.first {
            selectedTargetID = firstTarget.uuid
        }
    }

    /// Resolves the URL to the Info.plist file of the currently selected target.
    /// Never returns any internal SwiftCode bundle/source files.
    public func resolveInfoPlist(for project: Project) -> URL? {
        guard let targetID = selectedTargetID else {
            logger.info("No active target selected for plist resolution.")
            return nil
        }

        // Find the target inside any parsed project model
        for (projectURL, model) in parsedProjects {
            guard let target = model.targets.first(where: { $0.uuid == targetID }) else { continue }

            // Check target build settings in configurations
            if let configListUUID = target.buildConfigurationListUUID {
                // Find all matching configurations
                let configs = model.buildConfigurations.filter { config in
                    // In a standard pbxproj, the configuration is linked via build configuration list
                    // or scanned directly.
                    return true
                }

                for config in configs {
                    if let plistPath = config.buildSettings["INFOPLIST_FILE"] {
                        let cleanPath = plistPath.replacingOccurrences(of: "\"", with: "")
                        let resolvedURL = project.directoryURL.appendingPathComponent(cleanPath)
                        if FileManager.default.fileExists(atPath: resolvedURL.path) {
                            logger.info("Resolved Info.plist from build settings: \(cleanPath, privacy: .public)")
                            return resolvedURL
                        }
                    }
                }
            }

            // Fallback: search for Info.plist belonging to this target by searching PBXFileReferences
            for fileRef in model.fileReferences {
                if let name = fileRef.name, name == "Info.plist", let path = fileRef.path {
                    let cleanPath = path.replacingOccurrences(of: "\"", with: "")
                    let resolvedURL = project.directoryURL.appendingPathComponent(cleanPath)
                    if FileManager.default.fileExists(atPath: resolvedURL.path) {
                        logger.info("Resolved Info.plist from file references: \(cleanPath, privacy: .public)")
                        return resolvedURL
                    }
                }
            }
        }

        // Project directory fallback: search ONLY within the currently opened project's directory,
        // and strictly exclude the internal SwiftCode app files unless the opened project IS SwiftCode.
        let isOpeningSwiftCodeItself = project.name.lowercased() == "swiftcode"
        let fm = FileManager.default
        let projectDir = project.directoryURL

        // Scan project files using local enumerator
        if let enumerator = fm.enumerator(at: projectDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.lastPathComponent == "Info.plist" {
                    let pathString = fileURL.path
                    if !isOpeningSwiftCodeItself && (pathString.contains("/SwiftCode/Info.plist") || pathString.contains("SwiftCode.app")) {
                        // Exclude internal fallbacks
                        continue
                    }
                    logger.info("Resolved Info.plist from fallback directory scan: \(fileURL.lastPathComponent, privacy: .public)")
                    return fileURL
                }
            }
        }

        logger.warning("No valid Info.plist resolved for the active project.")
        return nil
    }

    /// Resolves the URL to the entitlements file of the currently selected target.
    /// Never returns any internal SwiftCode bundle/source files.
    public func resolveEntitlements(for project: Project) -> URL? {
        guard let targetID = selectedTargetID else {
            logger.info("No active target selected for entitlements resolution.")
            return nil
        }

        for (projectURL, model) in parsedProjects {
            guard let target = model.targets.first(where: { $0.uuid == targetID }) else { continue }

            // Check target build settings in configurations
            if let configListUUID = target.buildConfigurationListUUID {
                let configs = model.buildConfigurations
                for config in configs {
                    if let entitlementsPath = config.buildSettings["CODE_SIGN_ENTITLEMENTS"] {
                        let cleanPath = entitlementsPath.replacingOccurrences(of: "\"", with: "")
                        let resolvedURL = project.directoryURL.appendingPathComponent(cleanPath)
                        if FileManager.default.fileExists(atPath: resolvedURL.path) {
                            logger.info("Resolved Entitlements from build settings: \(cleanPath, privacy: .public)")
                            return resolvedURL
                        }
                    }
                }
            }

            // Fallback: search PBXFileReferences
            for fileRef in model.fileReferences {
                if let name = fileRef.name, name.hasSuffix(".entitlements"), let path = fileRef.path {
                    let cleanPath = path.replacingOccurrences(of: "\"", with: "")
                    let resolvedURL = project.directoryURL.appendingPathComponent(cleanPath)
                    if FileManager.default.fileExists(atPath: resolvedURL.path) {
                        logger.info("Resolved Entitlements from file references: \(cleanPath, privacy: .public)")
                        return resolvedURL
                    }
                }
            }
        }

        // Project directory fallback: search ONLY within the currently opened project's directory,
        // and strictly exclude internal SwiftCode.entitlements files.
        let isOpeningSwiftCodeItself = project.name.lowercased() == "swiftcode"
        let fm = FileManager.default
        let projectDir = project.directoryURL

        if let enumerator = fm.enumerator(at: projectDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "entitlements" {
                    let pathString = fileURL.path
                    if !isOpeningSwiftCodeItself && (pathString.contains("/SwiftCode/Resources/") || pathString.contains("SwiftCode.entitlements")) {
                        // Exclude internal fallbacks
                        continue
                    }
                    logger.info("Resolved Entitlements from fallback directory scan: \(fileURL.lastPathComponent, privacy: .public)")
                    return fileURL
                }
            }
        }

        logger.warning("No valid entitlements resolved for the active project.")
        return nil
    }
}
