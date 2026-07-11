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
}

public struct PBXTarget: Sendable, Identifiable {
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
            buildPhases: buildPhases
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
                let name: String?
                if match.range(at: 2).location != NSNotFound,
                   let nameRange = Range(match.range(at: 2), in: text) {
                    name = String(text[nameRange])
                } else {
                    name = nil
                }
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
            buildPhases: buildPhases
        )
    }
}
