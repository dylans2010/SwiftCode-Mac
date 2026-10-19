import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.BuildSystem", category: "XcodeProjParse")

// MARK: - Models

public struct XcodeProjModel: Sendable, Identifiable {
    public var id: String { projectURL.path }
    public let projectURL: URL
    public let rootObjectUUID: String
    public let targets: [PBXTarget]
    public let groups: [PBXGroup]
    public let fileReferences: [PBXFileReference]
    public let buildConfigurations: [PBXBuildConfiguration]
    public let buildPhases: [PBXBuildPhase]
    public let buildFiles: [String: String] // buildFileUUID -> fileRefUUID
}

public struct PBXTarget: Sendable, Identifiable, Hashable {
    public var id: String { uuid }
    public let uuid: String
    public let name: String
    public let productType: String?
    public let buildConfigurationListUUID: String?
    public let buildPhaseUUIDs: [String]
    public let dependencies: [String]
}

public struct PBXGroup: Sendable, Identifiable {
    public var id: String { uuid }
    public let uuid: String
    public let name: String?
    public let path: String?
    public let childrenUUIDs: [String]
}

public struct PBXFileReference: Sendable, Identifiable {
    public var id: String { uuid }
    public let uuid: String
    public let name: String?
    public let path: String?
    public let lastKnownFileType: String?
    public let sourceTree: String?
}

public struct PBXBuildConfiguration: Sendable, Identifiable {
    public var id: String { uuid }
    public let uuid: String
    public let name: String
    public let buildSettings: [String: String]
}

public struct PBXBuildPhase: Sendable, Identifiable {
    public var id: String { uuid }
    public let uuid: String
    public let isa: String
    public let files: [String] // Build file UUIDs
}

// MARK: - XcodeProjParse Service

public final class XcodeProjParse: Sendable {
    public static let shared = XcodeProjParse()

    private init() {}

    /// Parses an xcodeproj directory or a pbxproj file.
    public func parse(projectURL: URL) throws -> XcodeProjModel {
        var pbxprojURL = projectURL
        if projectURL.pathExtension == "xcodeproj" {
            pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
        }

        logger.info("Starting pbxproj parsing at: \(pbxprojURL.path, privacy: .public)")

        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            logger.error("pbxproj file does not exist at: \(pbxprojURL.path, privacy: .public)")
            throw NSError(domain: "XcodeProjParse", code: 404, userInfo: [NSLocalizedDescriptionKey: "project.pbxproj not found at \(pbxprojURL.path)"])
        }

        let data = try Data(contentsOf: pbxprojURL)

        var format: PropertyListSerialization.PropertyListFormat = .openStep
        let plist: [String: Any]

        do {
            if let parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] {
                plist = parsed
            } else {
                plist = [:]
            }
        } catch {
            logger.warning("Standard PropertyListSerialization failed: \(error.localizedDescription). Falling back to manual text scanning.")
            // Safe manual scanning fallback in case serialization is not supported on some Linux sandbox environments
            return try parseManual(data: data, projectURL: projectURL)
        }

        let rootObjectUUID = plist["rootObject"] as? String ?? ""
        let objects = plist["objects"] as? [String: [String: Any]] ?? [:]

        var targets: [PBXTarget] = []
        var groups: [PBXGroup] = []
        var fileReferences: [PBXFileReference] = []
        var buildConfigurations: [PBXBuildConfiguration] = []
        var buildPhases: [PBXBuildPhase] = []
        var buildFiles: [String: String] = [:]

        for (uuid, dict) in objects {
            guard let isa = dict["isa"] as? String else { continue }

            switch isa {
            case "PBXNativeTarget", "PBXAggregateTarget", "PBXLegacyTarget":
                let name = dict["name"] as? String ?? "Unnamed Target"
                let productType = dict["productType"] as? String
                let buildConfigurationListUUID = dict["buildConfigurationList"] as? String
                let buildPhaseUUIDs = dict["buildPhases"] as? [String] ?? []
                let dependencies = dict["dependencies"] as? [String] ?? []
                targets.append(PBXTarget(
                    uuid: uuid,
                    name: name,
                    productType: productType,
                    buildConfigurationListUUID: buildConfigurationListUUID,
                    buildPhaseUUIDs: buildPhaseUUIDs,
                    dependencies: dependencies
                ))

            case "PBXGroup", "PBXVariantGroup":
                let name = dict["name"] as? String
                let path = dict["path"] as? String
                let children = dict["children"] as? [String] ?? []
                groups.append(PBXGroup(
                    uuid: uuid,
                    name: name,
                    path: path,
                    childrenUUIDs: children
                ))

            case "PBXFileReference":
                let name = dict["name"] as? String
                let path = dict["path"] as? String
                let lastKnownFileType = dict["lastKnownFileType"] as? String
                let sourceTree = dict["sourceTree"] as? String
                fileReferences.append(PBXFileReference(
                    uuid: uuid,
                    name: name,
                    path: path,
                    lastKnownFileType: lastKnownFileType,
                    sourceTree: sourceTree
                ))

            case "XCBuildConfiguration":
                let name = dict["name"] as? String ?? "Unnamed Config"
                let rawSettings = dict["buildSettings"] as? [String: Any] ?? [:]
                var settings: [String: String] = [:]
                for (key, val) in rawSettings {
                    settings[key] = String(describing: val)
                }
                buildConfigurations.append(PBXBuildConfiguration(
                    uuid: uuid,
                    name: name,
                    buildSettings: settings
                ))

            case "PBXBuildFile":
                let fileRef = dict["fileRef"] as? String ?? ""
                buildFiles[uuid] = fileRef

            case "PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase", "PBXCopyFilesBuildPhase", "PBXShellScriptBuildPhase":
                let files = dict["files"] as? [String] ?? []
                buildPhases.append(PBXBuildPhase(
                    uuid: uuid,
                    isa: isa,
                    files: files
                ))

            default:
                break
            }
        }

        logger.info("Successfully parsed xcodeproj. Found: \(targets.count) targets, \(groups.count) groups, \(fileReferences.count) files.")

        return XcodeProjModel(
            projectURL: projectURL,
            rootObjectUUID: rootObjectUUID,
            targets: targets.sorted(by: { $0.name < $1.name }),
            groups: groups,
            fileReferences: fileReferences,
            buildConfigurations: buildConfigurations,
            buildPhases: buildPhases,
            buildFiles: buildFiles
        )
    }

    /// Fallback manual scanner for parsing pbxproj format using regex and line-by-line reading.
    private func parseManual(data: Data, projectURL: URL) throws -> XcodeProjModel {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "XcodeProjParse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 pbxproj file"])
        }

        var targets: [PBXTarget] = []
        var groups: [PBXGroup] = []
        var fileReferences: [PBXFileReference] = []
        var buildConfigurations: [PBXBuildConfiguration] = []
        var buildPhases: [PBXBuildPhase] = []

        // Scan for NativeTargets
        // Match UUID /* name */ = { isa = PBXNativeTarget; ... }
        let targetRegex = try NSRegularExpression(pattern: #"([A-Z0-9]{24})\s*/\* ([^*]+) \*/\s*=\s*\{\s*isa\s*=\s*(PBXNativeTarget|PBXAggregateTarget);[^}]*\}"#, options: [])
        let targetMatches = targetRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        for match in targetMatches {
            if let uuidRange = Range(match.range(at: 1), in: text),
               let nameRange = Range(match.range(at: 2), in: text) {
                let uuid = String(text[uuidRange])
                let name = String(text[nameRange])
                targets.append(PBXTarget(
                    uuid: uuid,
                    name: name,
                    productType: nil,
                    buildConfigurationListUUID: nil,
                    buildPhaseUUIDs: [],
                    dependencies: []
                ))
            }
        }

        // Scan for Groups
        let groupRegex = try NSRegularExpression(pattern: #"([A-Z0-9]{24})\s*/\* ([^*]*) \*/\s*=\s*\{\s*isa\s*=\s*(PBXGroup|PBXVariantGroup);[^}]*\}"#, options: [])
        let groupMatches = groupRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        for match in groupMatches {
            if let uuidRange = Range(match.range(at: 1), in: text) {
                let uuid = String(text[uuidRange])
                let name = match.range(at: 2).location != NSNotFound ? String(text[Range(match.range(at: 2), in: text)!]) : nil
                groups.append(PBXGroup(
                    uuid: uuid,
                    name: name,
                    path: nil,
                    childrenUUIDs: []
                ))
            }
        }

        // Scan for FileReferences
        let fileRegex = try NSRegularExpression(pattern: #"([A-Z0-9]{24})\s*/\* ([^*]+) \*/\s*=\s*\{\s*isa\s*=\s*PBXFileReference;[^}]*path\s*=\s*([^;]+);[^}]*\}"#, options: [])
        let fileMatches = fileRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        for match in fileMatches {
            if let uuidRange = Range(match.range(at: 1), in: text),
               let nameRange = Range(match.range(at: 2), in: text),
               let pathRange = Range(match.range(at: 3), in: text) {
                let uuid = String(text[uuidRange])
                let name = String(text[nameRange])
                let path = String(text[pathRange]).replacingOccurrences(of: "\"", with: "")
                fileReferences.append(PBXFileReference(
                    uuid: uuid,
                    name: name,
                    path: path,
                    lastKnownFileType: nil,
                    sourceTree: nil
                ))
            }
        }

        return XcodeProjModel(
            projectURL: projectURL,
            rootObjectUUID: "",
            targets: targets,
            groups: groups,
            fileReferences: fileReferences,
            buildConfigurations: buildConfigurations,
            buildPhases: buildPhases,
            buildFiles: [:]
        )
    }
}

@MainActor
public final class XcodeProjWriter {
    public static let shared = XcodeProjWriter()

    private init() {}

    private func resolvePbxprojURL(for projectURL: URL) -> URL {
        if projectURL.pathExtension == "xcodeproj" {
            return projectURL.appendingPathComponent("project.pbxproj")
        }
        return projectURL.appendingPathComponent("project.pbxproj")
    }

    /// Updates or inserts a build setting key-value pair in project.pbxproj
    @discardableResult
    public func updateBuildSetting(
        key: String,
        value: String,
        configurationName: String? = nil,
        projectURL: URL
    ) throws -> XcodeProjModel {
        let pbxprojURL = resolvePbxprojURL(for: projectURL)
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            throw NSError(domain: "XcodeProjWriter", code: 404, userInfo: [NSLocalizedDescriptionKey: "project.pbxproj not found at \(pbxprojURL.path)"])
        }

        var content = try String(contentsOf: pbxprojURL, encoding: .utf8)

        // Escape value if needed
        let formattedValue = value.contains(" ") || value.contains("$") || value.contains("/") || value.contains("-") ? "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\"" : value

        // Pattern for existing key in buildSettings
        let keyPattern = "(\\b" + NSRegularExpression.escapedPattern(for: key) + "\\s*=\\s*)([^;]+)(;)"
        if let regex = try? NSRegularExpression(pattern: keyPattern, options: []) {
            let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..<content.endIndex, in: content))
            if !matches.isEmpty {
                // Key exists: replace occurrences
                content = regex.stringByReplacingMatches(
                    in: content,
                    options: [],
                    range: NSRange(content.startIndex..<content.endIndex, in: content),
                    withTemplate: "$1\(formattedValue)$3"
                )
            } else {
                // Key doesn't exist: insert into buildSettings = { blocks
                let buildSettingsPattern = "(buildSettings\\s*=\\s*\\{)"
                if let bsRegex = try? NSRegularExpression(pattern: buildSettingsPattern, options: []) {
                    content = bsRegex.stringByReplacingMatches(
                        in: content,
                        options: [],
                        range: NSRange(content.startIndex..<content.endIndex, in: content),
                        withTemplate: "$1\n\t\t\t\t\(key) = \(formattedValue);"
                    )
                }
            }
        }

        try content.write(to: pbxprojURL, atomically: true, encoding: .utf8)

        let newModel = try XcodeProjParse.shared.parse(projectURL: projectURL)
        ProjectResolutionService.shared.parsedProjects[projectURL] = newModel
        return newModel
    }

    /// Removes a build setting key from project.pbxproj
    @discardableResult
    public func removeBuildSetting(
        key: String,
        configurationName: String? = nil,
        projectURL: URL
    ) throws -> XcodeProjModel {
        let pbxprojURL = resolvePbxprojURL(for: projectURL)
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            throw NSError(domain: "XcodeProjWriter", code: 404, userInfo: [NSLocalizedDescriptionKey: "project.pbxproj not found at \(pbxprojURL.path)"])
        }

        var content = try String(contentsOf: pbxprojURL, encoding: .utf8)
        let keyPattern = "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\s*=\\s*[^;]+;\\s*\\n?"
        if let regex = try? NSRegularExpression(pattern: keyPattern, options: []) {
            content = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: NSRange(content.startIndex..<content.endIndex, in: content),
                withTemplate: ""
            )
        }

        try content.write(to: pbxprojURL, atomically: true, encoding: .utf8)

        let newModel = try XcodeProjParse.shared.parse(projectURL: projectURL)
        ProjectResolutionService.shared.parsedProjects[projectURL] = newModel
        return newModel
    }

    /// Updates the target name and its product name in project.pbxproj
    @discardableResult
    public func updateTargetName(
        oldName: String,
        newName: String,
        projectURL: URL
    ) throws -> XcodeProjModel {
        let pbxprojURL = resolvePbxprojURL(for: projectURL)
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            throw NSError(domain: "XcodeProjWriter", code: 404, userInfo: [NSLocalizedDescriptionKey: "project.pbxproj not found at \(pbxprojURL.path)"])
        }

        var content = try String(contentsOf: pbxprojURL, encoding: .utf8)

        let namePattern = "(name\\s*=\\s*)(\"?)" + NSRegularExpression.escapedPattern(for: oldName) + "(\"?\\s*;)"
        if let regex = try? NSRegularExpression(pattern: namePattern, options: []) {
            content = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: NSRange(content.startIndex..<content.endIndex, in: content),
                withTemplate: "$1$2\(newName)$3"
            )
        }

        let prodNamePattern = "(productName\\s*=\\s*)(\"?)" + NSRegularExpression.escapedPattern(for: oldName) + "(\"?\\s*;)"
        if let regex = try? NSRegularExpression(pattern: prodNamePattern, options: []) {
            content = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: NSRange(content.startIndex..<content.endIndex, in: content),
                withTemplate: "$1$2\(newName)$3"
            )
        }

        try content.write(to: pbxprojURL, atomically: true, encoding: .utf8)

        let newModel = try XcodeProjParse.shared.parse(projectURL: projectURL)
        ProjectResolutionService.shared.parsedProjects[projectURL] = newModel
        return newModel
    }

    @discardableResult
    public func updateMarketingVersion(
        version: String,
        projectURL: URL
    ) throws -> XcodeProjModel {
        return try updateBuildSetting(key: "MARKETING_VERSION", value: version, projectURL: projectURL)
    }

    @discardableResult
    public func updateProjectVersion(
        build: String,
        projectURL: URL
    ) throws -> XcodeProjModel {
        return try updateBuildSetting(key: "CURRENT_PROJECT_VERSION", value: build, projectURL: projectURL)
    }

    @discardableResult
    public func updateBundleIdentifier(
        bundleID: String,
        projectURL: URL
    ) throws -> XcodeProjModel {
        return try updateBuildSetting(key: "PRODUCT_BUNDLE_IDENTIFIER", value: bundleID, projectURL: projectURL)
    }

    @discardableResult
    public func updateDeploymentTarget(
        platformKey: String,
        version: String,
        projectURL: URL
    ) throws -> XcodeProjModel {
        return try updateBuildSetting(key: platformKey, value: version, projectURL: projectURL)
    }

    /// Adds and registers a file in project.pbxproj:
    /// - Adds PBXFileReference
    /// - Adds PBXBuildFile in PBXSourcesBuildPhase (if source) or PBXResourcesBuildPhase (if resource)
    /// - Adds to PBXGroup children
    @discardableResult
    public func addFileReference(
        filePath: String,
        projectURL: URL? = nil
    ) throws -> XcodeProjModel {
        let effectiveProjectURL: URL
        if let projectURL {
            effectiveProjectURL = projectURL
        } else if let coordURL = DocumentCoordinator.shared.projectURL {
            effectiveProjectURL = coordURL
        } else if let sessionURL = ProjectSessionStore.shared.activeProject?.directoryURL {
            effectiveProjectURL = sessionURL
        } else {
            throw NSError(domain: "XcodeProjWriter", code: 404, userInfo: [NSLocalizedDescriptionKey: "No active Xcode project found."])
        }

        let xcodeprojURL: URL
        if effectiveProjectURL.pathExtension == "xcodeproj" {
            xcodeprojURL = effectiveProjectURL
        } else {
            let fm = FileManager.default
            if let entries = try? fm.contentsOfDirectory(at: effectiveProjectURL, includingPropertiesForKeys: nil),
               let proj = entries.first(where: { $0.pathExtension == "xcodeproj" }) {
                xcodeprojURL = proj
            } else {
                xcodeprojURL = effectiveProjectURL
            }
        }

        let pbxprojURL = resolvePbxprojURL(for: xcodeprojURL)
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            throw NSError(domain: "XcodeProjWriter", code: 404, userInfo: [NSLocalizedDescriptionKey: "project.pbxproj not found at \(pbxprojURL.path)"])
        }

        var content = try String(contentsOf: pbxprojURL, encoding: .utf8)
        let fileName = (filePath as NSString).lastPathComponent
        let fileExt = (filePath as NSString).pathExtension.lowercased()

        // Check if already registered
        if content.contains("/* \(fileName) */") || content.contains("/* \(fileName) in Sources */") || content.contains("/* \(fileName) in Resources */") {
            return try XcodeProjParse.shared.parse(projectURL: xcodeprojURL)
        }

        let fileRefID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24).uppercased())
        let buildFileID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24).uppercased())

        let isSourceCode = ["swift", "m", "mm", "c", "cpp"].contains(fileExt)
        let isResource = ["xcstrings", "strings", "stringsdict", "storyboard", "xib", "png", "jpg", "jpeg", "json", "plist", "sh", "txt"].contains(fileExt)

        let fileType: String
        switch fileExt {
        case "swift": fileType = "sourcecode.swift"
        case "m", "c": fileType = "sourcecode.c.c"
        case "mm", "cpp": fileType = "sourcecode.cpp.cpp"
        case "h": fileType = "sourcecode.c.h"
        case "xcstrings": fileType = "text.json.xcstrings"
        case "strings": fileType = "text.plist.strings"
        case "plist": fileType = "text.plist.xml"
        case "sh": fileType = "text.script.sh"
        default: fileType = "text"
        }

        // 1. Add to PBXFileReference section
        let fileRefEntry = "\t\t\(fileRefID) /* \(fileName) */ = {isa = PBXFileReference; lastKnownFileType = \(fileType); path = \(fileName); sourceTree = \"<group>\"; };\n"
        if let range = content.range(of: "/* Begin PBXFileReference section */") {
            content.insert(contentsOf: fileRefEntry, at: range.upperBound)
        }

        // 2. Add to PBXBuildFile section if source or resource
        if isSourceCode {
            let buildFileEntry = "\t\t\(buildFileID) /* \(fileName) in Sources */ = {isa = PBXBuildFile; fileRef = \(fileRefID) /* \(fileName) */; };\n"
            if let range = content.range(of: "/* Begin PBXBuildFile section */") {
                content.insert(contentsOf: buildFileEntry, at: range.upperBound)
            }
            if let phaseRange = content.range(of: "/* Sources */ = {") {
                let searchRange = phaseRange.lowerBound..<content.endIndex
                if let filesRange = content.range(of: "files = (\n", options: [], range: searchRange) {
                    content.insert(contentsOf: "\t\t\t\t\(buildFileID) /* \(fileName) in Sources */,\n", at: filesRange.upperBound)
                }
            }
        } else if isResource {
            let buildFileEntry = "\t\t\(buildFileID) /* \(fileName) in Resources */ = {isa = PBXBuildFile; fileRef = \(fileRefID) /* \(fileName) */; };\n"
            if let range = content.range(of: "/* Begin PBXBuildFile section */") {
                content.insert(contentsOf: buildFileEntry, at: range.upperBound)
            }
            if let phaseRange = content.range(of: "/* Resources */ = {") {
                let searchRange = phaseRange.lowerBound..<content.endIndex
                if let filesRange = content.range(of: "files = (\n", options: [], range: searchRange) {
                    content.insert(contentsOf: "\t\t\t\t\(buildFileID) /* \(fileName) in Resources */,\n", at: filesRange.upperBound)
                }
            }
        }

        // 3. Add to Main Group or matching group's children
        if let mainGroupRange = content.range(of: "children = (\n") {
            content.insert(contentsOf: "\t\t\t\t\(fileRefID) /* \(fileName) */,\n", at: mainGroupRange.upperBound)
        }

        try content.write(to: pbxprojURL, atomically: true, encoding: .utf8)
        let newModel = try XcodeProjParse.shared.parse(projectURL: xcodeprojURL)
        ProjectResolutionService.shared.parsedProjects[xcodeprojURL] = newModel
        return newModel
    }
}
