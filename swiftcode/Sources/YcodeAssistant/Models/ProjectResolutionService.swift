import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Services", category: "ProjectResolution")

@Observable
@MainActor
public final class ProjectResolutionService: Sendable {
    public static let shared = ProjectResolutionService()

    public var parsedProjects: [URL: XcodeProjModel] = [:]

    public var selectedTargetID: String? {
        didSet {
            logger.info("Selected target changed to: \(self.selectedTargetID ?? "None", privacy: .public)")
        }
    }

    private init() {}

    public func updateParsedProjects(with models: [URL: XcodeProjModel]) {
        for (url, model) in models {
            self.parsedProjects[url] = model
        }
        if selectedTargetID == nil, let firstModel = models.values.first, let firstTarget = firstModel.targets.first {
            selectedTargetID = firstTarget.uuid
        }
    }

    public func resolveInfoPlist(for model: XcodeProjModel, targetID: String? = nil) -> URL? {
        updateParsedProjects(with: [model.projectURL: model])
        let tid = targetID ?? selectedTargetID ?? model.targets.first?.uuid
        let target = model.targets.first(where: { $0.uuid == tid }) ?? model.targets.first
        let projectDir = model.projectURL.deletingLastPathComponent()

        if let target = target {
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

            let targetPlist = projectDir.appendingPathComponent(target.name).appendingPathComponent("Info.plist")
            if isRegularFile(at: targetPlist) {
                return targetPlist
            }
        }

        let rootPlist = projectDir.appendingPathComponent("Info.plist")
        if isRegularFile(at: rootPlist) {
            return rootPlist
        }

        return scanForFirstFile(named: "Info.plist", in: projectDir)
    }

    public func resolveEntitlements(for model: XcodeProjModel, targetID: String? = nil) -> URL? {
        updateParsedProjects(with: [model.projectURL: model])
        let tid = targetID ?? selectedTargetID ?? model.targets.first?.uuid
        let target = model.targets.first(where: { $0.uuid == tid }) ?? model.targets.first
        let projectDir = model.projectURL.deletingLastPathComponent()

        if let target = target {
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

            let targetEnt = projectDir.appendingPathComponent(target.name).appendingPathComponent("\(target.name).entitlements")
            if isRegularFile(at: targetEnt) {
                return targetEnt
            }
            let targetEntAtRoot = projectDir.appendingPathComponent("\(target.name).entitlements")
            if isRegularFile(at: targetEntAtRoot) {
                return targetEntAtRoot
            }
        }

        return scanForFirstFileWithExtension("entitlements", in: projectDir)
    }

    public func resolveInfoPlist(for project: Project) -> URL? {
        let targetID = selectedTargetID ?? parsedProjects.values.first?.targets.first?.uuid
        let projectDir = project.directoryURL

        for (_, model) in parsedProjects {
            let target = (targetID != nil ? model.targets.first(where: { $0.uuid == targetID }) : nil) ?? model.targets.first
            guard let activeTarget = target else { continue }

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

            let candidate = projectDir.appendingPathComponent(activeTarget.name).appendingPathComponent("Info.plist")
            if isRegularFile(at: candidate) {
                return candidate
            }
        }

        let rootCandidate = projectDir.appendingPathComponent("Info.plist")
        if isRegularFile(at: rootCandidate) {
            return rootCandidate
        }

        return scanForFirstFile(named: "Info.plist", in: projectDir, isSelfProject: project.name.lowercased() == "swiftcode")
    }

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
