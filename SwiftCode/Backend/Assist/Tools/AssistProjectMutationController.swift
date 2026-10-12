import Foundation

/// Adds/removes file references in the *user's* `project.pbxproj`.
///
/// Group IDs and the Sources build-phase ID are resolved dynamically from the
/// target pbxproj — nothing here is hardcoded to any particular project.
@MainActor
public struct AssistProjectMutationController: AssistTool {
    public let id = "project_mutation_controller"
    public let name = "Xcode Project Mutation Controller"
    public let description = "Adds/removes file references in the user's project.pbxproj, resolving groups and build phases from the target project."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Adds or removes file references in the user's project.pbxproj, or repairs its formatting. Targets the project found in the workspace root unless projectFile is given.",
            properties: [
                "action": JSONSchema(type: "string", description: "One of 'add', 'remove', or 'repair'."),
                "projectFile": JSONSchema(type: "string", description: "Workspace-relative path to project.pbxproj. Defaults to the project.pbxproj of the project found in the workspace root."),
                "filePath": JSONSchema(type: "string", description: "Workspace-relative file path. Required for 'add' and 'remove'.")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let action = (input["action"] as? String ?? "").lowercased()
        guard !action.isEmpty else { return .failure("Missing action: add/remove/repair") }

        // Resolve the target project.pbxproj: explicit param wins, otherwise
        // the user's project in the workspace root.
        let pbxPath: String
        if let explicit = input["projectFile"] as? String, !explicit.isEmpty {
            pbxPath = explicit
        } else if let located = AssistXcodeProjectResolver.locate(in: context.workspaceRoot),
                  let pbxURL = located.pbxprojURL {
            pbxPath = pbxURL.path.replacingOccurrences(of: context.workspaceRoot.path + "/", with: "")
        } else {
            return .failure("No Xcode project (.xcodeproj) found in the workspace root. Pass projectFile explicitly.")
        }

        let pbx: String
        do {
            pbx = try context.fileSystem.readFile(at: pbxPath)
        } catch {
            return .failure("Could not read \(pbxPath): \(error.localizedDescription)")
        }
        var updated = pbx

        switch action {
        case "repair":
            updated = updated.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            try context.fileSystem.writeFile(at: pbxPath, content: updated)
            return .success("Project mutation complete: \(action)", data: ["project": pbxPath])

        case "add":
            guard let filePath = input["filePath"] as? String else { return .failure("Missing filePath") }
            return addFile(filePath: filePath, pbxPath: pbxPath, pbx: updated, context: context)

        case "remove":
            guard let file = input["filePath"] as? String else { return .failure("Missing filePath") }
            updated = updated
                .components(separatedBy: .newlines)
                .filter { !$0.contains(file) }
                .joined(separator: "\n")
            try context.fileSystem.writeFile(at: pbxPath, content: updated)
            return .success("Project mutation complete: \(action)", data: ["project": pbxPath])

        default:
            return .failure("Unsupported action: \(action)")
        }
    }

    private func addFile(filePath: String, pbxPath: String, pbx: String, context: AssistContext) -> AssistToolResult {
        var updated = pbx
        let fileName = (filePath as NSString).lastPathComponent
        let fileDir = (filePath as NSString).deletingLastPathComponent

        // Check if already registered
        if updated.contains(filePath) || updated.contains(fileName) {
            return .success("File already referenced in project.pbxproj: \(filePath)")
        }

        // Resolve the target group from the pbxproj's own group structure.
        // Prefer an exact directory match, then the deepest path-prefix match.
        guard let groupUUID = AssistXcodeProjectResolver.groupID(forFileDirectory: fileDir, inPbxproj: updated) else {
            return .failure("No matching group found in \(pbxPath) for directory '\(fileDir)'. Create the group in Xcode first or pass a filePath inside an existing group.")
        }

        // Resolve the Sources build phase dynamically.
        guard let sourcesPhaseID = AssistXcodeProjectResolver.sourcesBuildPhaseID(inPbxproj: updated) else {
            return .failure("No PBXSourcesBuildPhase ('Sources') found in \(pbxPath).")
        }

        let fileId = generateRandomHexID()
        let buildFileId = generateRandomHexID()

        // 1. Add to PBXBuildFile section
        let buildFileEntry = "\t\t\(buildFileId) /* \(fileName) in Sources */ = {isa = PBXBuildFile; fileRef = \(fileId) /* \(fileName) */; };\n"
        if let buildFileRange = updated.range(of: "/* Begin PBXBuildFile section */") {
            updated.insert(contentsOf: buildFileEntry, at: buildFileRange.upperBound)
        } else {
            return .failure("PBXBuildFile section not found")
        }

        // 2. Add to PBXFileReference section (group-relative path, Xcode-idiomatic)
        let fileRefEntry = "\t\t\(fileId) /* \(fileName) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \(fileName); sourceTree = \"<group>\"; };\n"
        if let fileRefRange = updated.range(of: "/* Begin PBXFileReference section */") {
            updated.insert(contentsOf: fileRefEntry, at: fileRefRange.upperBound)
        } else {
            return .failure("PBXFileReference section not found")
        }

        // 3. Add to the resolved group's children array
        let groupStartStr = "\(groupUUID) /*"
        if let groupIndex = updated.range(of: groupStartStr) {
            let searchRange = groupIndex.lowerBound..<updated.endIndex
            if let childrenRange = updated.range(of: "children = (\n", options: [], range: searchRange) {
                let childrenEntry = "\t\t\t\t\(fileId) /* \(fileName) */,\n"
                updated.insert(contentsOf: childrenEntry, at: childrenRange.upperBound)
            } else {
                return .failure("children block not found in group \(groupUUID)")
            }
        } else {
            return .failure("Group definition not found: \(groupUUID)")
        }

        // 4. Add to the Sources build phase's files
        let phaseStartStr = "\(sourcesPhaseID) /* Sources */ = {"
        if let phaseIndex = updated.range(of: phaseStartStr) {
            let searchRange = phaseIndex.lowerBound..<updated.endIndex
            if let filesRange = updated.range(of: "files = (\n", options: [], range: searchRange) {
                let filesEntry = "\t\t\t\t\(buildFileId) /* \(fileName) in Sources */,\n"
                updated.insert(contentsOf: filesEntry, at: filesRange.upperBound)
            } else {
                return .failure("files block not found in Sources build phase")
            }
        } else {
            return .failure("Sources build phase \(sourcesPhaseID) not found")
        }

        do {
            try context.fileSystem.writeFile(at: pbxPath, content: updated)
        } catch {
            return .failure("Failed writing \(pbxPath): \(error.localizedDescription)")
        }
        return .success("Project mutation complete: added \(fileName) via 4-step registration protocol", data: ["project": pbxPath])
    }

    private func generateRandomHexID() -> String {
        let chars = Array("0123456789ABCDEF")
        return String((0..<24).compactMap { _ in chars.randomElement() })
    }
}
