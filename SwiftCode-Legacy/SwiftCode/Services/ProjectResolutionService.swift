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
        for (url, model) in models {
            self.parsedProjects[url] = model
        }
        if selectedTargetID == nil, let firstModel = models.values.first, let firstTarget = firstModel.targets.first {
            selectedTargetID = firstTarget.uuid
        }
    }

    /// Resolves the URL to the Info.plist file directly from an XcodeProjModel and optional target UUID.
    public func resolveInfoPlist(for model: XcodeProjModel, targetID: String? = nil) -> URL? {
        updateParsedProjects(with: [model.projectURL: model])
        let tid = targetID ?? selectedTargetID ?? model.targets.first?.uuid
        let target = model.targets.first(where: { $0.uuid == tid }) ?? model.targets.first
        let projectDir = model.projectURL.deletingLastPathComponent()

        if let target = target {
            // 1. Check build settings for INFOPLIST_FILE
            let configs = model.buildConfigurations
            for config in configs {
                if let rawPath = config.buildSettings["INFOPLIST_FILE"] {
                    let expanded = expandXcodeBuildVariables(rawPath, target: target, projectDir: projectDir)
                    if !expanded.isEmpty {
                        let candidate = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : projectDir.appendingPathComponent(expanded)
                        if isRegularFile(at: candidate) {
                            logger.info("Resolved Info.plist from model build settings: \(candidate.path, privacy: .public)")
                            return candidate
                        }
                    }
                }
            }

            // 2. Check PBXFileReferences
            for fileRef in model.fileReferences {
                if let name = fileRef.name, name == "Info.plist", let path = fileRef.path {
                    let expanded = expandXcodeBuildVariables(path, target: target, projectDir: projectDir)
                    if !expanded.isEmpty {
                        let candidate = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : projectDir.appendingPathComponent(expanded)
                        if isRegularFile(at: candidate) {
                            logger.info("Resolved Info.plist from model file references: \(candidate.path, privacy: .public)")
                            return candidate
                        }
                    }
                }
            }

            // 3. Known standard locations for target
            let targetPlist = projectDir.appendingPathComponent(target.name).appendingPathComponent("Info.plist")
            if isRegularFile(at: targetPlist) {
                return targetPlist
            }
        }

        // 4. Root Info.plist
        let rootPlist = projectDir.appendingPathComponent("Info.plist")
        if isRegularFile(at: rootPlist) {
            return rootPlist
        }

        // 5. Recursive fallback scan (excluding build directories and internal bundles)
        return scanForFirstFile(named: "Info.plist", in: projectDir)
    }

    /// Resolves the URL to the entitlements file directly from an XcodeProjModel and optional target UUID.
    public func resolveEntitlements(for model: XcodeProjModel, targetID: String? = nil) -> URL? {
        updateParsedProjects(with: [model.projectURL: model])
        let tid = targetID ?? selectedTargetID ?? model.targets.first?.uuid
        let target = model.targets.first(where: { $0.uuid == tid }) ?? model.targets.first
        let projectDir = model.projectURL.deletingLastPathComponent()

        if let target = target {
            // 1. Check build settings for CODE_SIGN_ENTITLEMENTS
            let configs = model.buildConfigurations
            for config in configs {
                if let rawPath = config.buildSettings["CODE_SIGN_ENTITLEMENTS"] {
                    let expanded = expandXcodeBuildVariables(rawPath, target: target, projectDir: projectDir)
                    if !expanded.isEmpty {
                        let candidate = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : projectDir.appendingPathComponent(expanded)
                        if isRegularFile(at: candidate) {
                            logger.info("Resolved Entitlements from model build settings: \(candidate.path, privacy: .public)")
                            return candidate
                        }
                    }
                }
            }

            // 2. Check PBXFileReferences
            for fileRef in model.fileReferences {
                if let name = fileRef.name, name.hasSuffix(".entitlements"), let path = fileRef.path {
                    let expanded = expandXcodeBuildVariables(path, target: target, projectDir: projectDir)
                    if !expanded.isEmpty {
                        let candidate = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : projectDir.appendingPathComponent(expanded)
                        if isRegularFile(at: candidate) {
                            logger.info("Resolved Entitlements from model file references: \(candidate.path, privacy: .public)")
                            return candidate
                        }
                    }
                }
            }

            // 3. Known standard locations for target
            let targetEnt = projectDir.appendingPathComponent(target.name).appendingPathComponent("\(target.name).entitlements")
            if isRegularFile(at: targetEnt) {
                return targetEnt
            }
            let targetEntAtRoot = projectDir.appendingPathComponent("\(target.name).entitlements")
            if isRegularFile(at: targetEntAtRoot) {
                return targetEntAtRoot
            }
        }

        // 4. Recursive scan for *.entitlements
        return scanForFirstFileWithExtension("entitlements", in: projectDir)
    }

    /// Resolves the URL to the Info.plist file of the currently selected target.
    /// Never returns any internal SwiftCode bundle/source files or directory URLs.
    public func resolveInfoPlist(for project: Project) -> URL? {
        let targetID = selectedTargetID ?? parsedProjects.values.first?.targets.first?.uuid
        let projectDir = project.directoryURL

        // Find the target inside any parsed project model
        for (_, model) in parsedProjects {
            let target = (targetID != nil ? model.targets.first(where: { $0.uuid == targetID }) : nil) ?? model.targets.first
            guard let activeTarget = target else { continue }

            // Check target build settings in configurations
            for config in model.buildConfigurations {
                if let plistPath = config.buildSettings["INFOPLIST_FILE"] {
                    let clean = expandXcodeBuildVariables(plistPath, target: activeTarget, projectDir: projectDir)
                    if !clean.isEmpty {
                        let candidate = clean.hasPrefix("/") ? URL(fileURLWithPath: clean) : projectDir.appendingPathComponent(clean)
                        if isRegularFile(at: candidate) {
                            logger.info("Resolved Info.plist from build settings: \(candidate.path, privacy: .public)")
                            return candidate
                        }
                    }
                }
            }

            // Fallback: search for Info.plist belonging to this target by searching PBXFileReferences
            for fileRef in model.fileReferences {
                if let name = fileRef.name, name == "Info.plist", let path = fileRef.path {
                    let clean = expandXcodeBuildVariables(path, target: activeTarget, projectDir: projectDir)
                    if !clean.isEmpty {
                        let candidate = clean.hasPrefix("/") ? URL(fileURLWithPath: clean) : projectDir.appendingPathComponent(clean)
                        if isRegularFile(at: candidate) {
                            logger.info("Resolved Info.plist from file references: \(candidate.path, privacy: .public)")
                            return candidate
                        }
                    }
                }
            }

            // Known target folder
            let candidate = projectDir.appendingPathComponent(activeTarget.name).appendingPathComponent("Info.plist")
            if isRegularFile(at: candidate) {
                return candidate
            }
        }

        // Root Info.plist
        let rootCandidate = projectDir.appendingPathComponent("Info.plist")
        if isRegularFile(at: rootCandidate) {
            return rootCandidate
        }

        // Project directory fallback: search ONLY within the currently opened project's directory,
        // strictly excluding internal SwiftCode app files unless the opened project IS SwiftCode.
        return scanForFirstFile(named: "Info.plist", in: projectDir, isSelfProject: project.name.lowercased() == "swiftcode")
    }

    /// Resolves the URL to the entitlements file of the currently selected target.
    /// Never returns any internal SwiftCode bundle/source files or directory URLs.
    public func resolveEntitlements(for project: Project) -> URL? {
        let targetID = selectedTargetID ?? parsedProjects.values.first?.targets.first?.uuid
        let projectDir = project.directoryURL

        for (_, model) in parsedProjects {
            let target = (targetID != nil ? model.targets.first(where: { $0.uuid == targetID }) : nil) ?? model.targets.first
            guard let activeTarget = target else { continue }

            for config in model.buildConfigurations {
                if let entitlementsPath = config.buildSettings["CODE_SIGN_ENTITLEMENTS"] {
                    let clean = expandXcodeBuildVariables(entitlementsPath, target: activeTarget, projectDir: projectDir)
                    if !clean.isEmpty {
                        let candidate = clean.hasPrefix("/") ? URL(fileURLWithPath: clean) : projectDir.appendingPathComponent(clean)
                        if isRegularFile(at: candidate) {
                            logger.info("Resolved Entitlements from build settings: \(candidate.path, privacy: .public)")
                            return candidate
                        }
                    }
                }
            }

            // Fallback: search PBXFileReferences
            for fileRef in model.fileReferences {
                if let name = fileRef.name, name.hasSuffix(".entitlements"), let path = fileRef.path {
                    let clean = expandXcodeBuildVariables(path, target: activeTarget, projectDir: projectDir)
                    if !clean.isEmpty {
                        let candidate = clean.hasPrefix("/") ? URL(fileURLWithPath: clean) : projectDir.appendingPathComponent(clean)
                        if isRegularFile(at: candidate) {
                            logger.info("Resolved Entitlements from file references: \(candidate.path, privacy: .public)")
                            return candidate
                        }
                    }
                }
            }

            // Known target name entitlements
            let targetEnt = projectDir.appendingPathComponent(activeTarget.name).appendingPathComponent("\(activeTarget.name).entitlements")
            if isRegularFile(at: targetEnt) {
                return targetEnt
            }
            let rootEnt = projectDir.appendingPathComponent("\(activeTarget.name).entitlements")
            if isRegularFile(at: rootEnt) {
                return rootEnt
            }
        }

        return scanForFirstFileWithExtension("entitlements", in: projectDir, isSelfProject: project.name.lowercased() == "swiftcode")
    }

    // MARK: - Private Helpers

    private func isRegularFile(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && !isDir.boolValue
    }

    private func expandXcodeBuildVariables(_ raw: String, target: PBXTarget, projectDir: URL) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        guard !path.isEmpty else { return "" }

        path = path.replacingOccurrences(of: "$(SRCROOT)", with: projectDir.path)
        path = path.replacingOccurrences(of: "${SRCROOT}", with: projectDir.path)
        path = path.replacingOccurrences(of: "$(PROJECT_DIR)", with: projectDir.path)
        path = path.replacingOccurrences(of: "${PROJECT_DIR}", with: projectDir.path)
        path = path.replacingOccurrences(of: "$(TARGET_NAME)", with: target.name)
        path = path.replacingOccurrences(of: "${TARGET_NAME}", with: target.name)
        path = path.replacingOccurrences(of: "$(PRODUCT_NAME)", with: target.name)
        path = path.replacingOccurrences(of: "${PRODUCT_NAME}", with: target.name)
        path = path.replacingOccurrences(of: "$(inherited)", with: "")
        path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return path
    }

    private func scanForFirstFile(named targetName: String, in rootDir: URL, isSelfProject: Bool = false) -> URL? {
        guard FileManager.default.fileExists(atPath: rootDir.path) else { return nil }
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let enumerator = fm.enumerator(at: rootDir, includingPropertiesForKeys: [.isRegularFileKey], options: options) else {
            return nil
        }

        while let fileURL = enumerator.nextObject() as? URL {
            let pathString = fileURL.path
            if pathString.contains("/DerivedData/") || pathString.contains("/.build/") || pathString.contains("/build/") || pathString.contains("/Pods/") {
                continue
            }
            if !isSelfProject && (pathString.contains("/SwiftCode/Info.plist") || pathString.contains("SwiftCode.app")) {
                continue
            }
            if fileURL.lastPathComponent == targetName && isRegularFile(at: fileURL) {
                logger.info("Found \(targetName, privacy: .public) via directory scan: \(fileURL.path, privacy: .public)")
                return fileURL
            }
        }
        return nil
    }

    private func scanForFirstFileWithExtension(_ ext: String, in rootDir: URL, isSelfProject: Bool = false) -> URL? {
        guard FileManager.default.fileExists(atPath: rootDir.path) else { return nil }
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let enumerator = fm.enumerator(at: rootDir, includingPropertiesForKeys: [.isRegularFileKey], options: options) else {
            return nil
        }

        while let fileURL = enumerator.nextObject() as? URL {
            let pathString = fileURL.path
            if pathString.contains("/DerivedData/") || pathString.contains("/.build/") || pathString.contains("/build/") || pathString.contains("/Pods/") {
                continue
            }
            if !isSelfProject && (pathString.contains("/SwiftCode/Resources/") || pathString.contains("SwiftCode.entitlements")) {
                continue
            }
            if fileURL.pathExtension == ext && isRegularFile(at: fileURL) {
                logger.info("Found .\(ext, privacy: .public) via directory scan: \(fileURL.path, privacy: .public)")
                return fileURL
            }
        }
        return nil
    }
}
