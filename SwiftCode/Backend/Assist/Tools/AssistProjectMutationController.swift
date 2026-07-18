import Foundation

@MainActor
public struct AssistProjectMutationController: AssistTool {
    public let id = "project_mutation_controller"
    public let name = "Xcode Project Mutation Controller"
    public let description = "Adds/removes files and repairs references in SwiftCode.xcodeproj/project.pbxproj."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let pbxPath = input["projectFile"] as? String ?? "SwiftCode.xcodeproj/project.pbxproj"
        let action = (input["action"] as? String ?? "").lowercased()
        guard !action.isEmpty else { return .failure("Missing action: add/remove/repair") }

        let pbx = try context.fileSystem.readFile(at: pbxPath)
        var updated = pbx

        switch action {
        case "repair":
            updated = updated.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            try context.fileSystem.writeFile(at: pbxPath, content: updated)
            return .success("Project mutation complete: \(action)", data: ["project": pbxPath])

        case "add":
            guard let filePath = input["filePath"] as? String else { return .failure("Missing filePath") }
            let fileName = (filePath as NSString).lastPathComponent

            // Check if already registered
            if updated.contains(filePath) || updated.contains(fileName) {
                return .success("File already referenced in project.pbxproj: \(filePath)")
            }

            let fileId = generateRandomHexID()
            let buildFileId = generateRandomHexID()

            // 1. Map path to group UUID
            let groupUUID: String
            if filePath.contains("Core/AI/Agent") {
                groupUUID = "9FAB492FE3914F789AA58201"
            } else if filePath.contains("Core/AI") {
                groupUUID = "DA941B6FA862048858B975DF"
            } else if filePath.contains("Tools/Agentic") {
                groupUUID = "D3C76C44A71C4A3EB65045B1"
            } else if filePath.contains("ViewModels") {
                groupUUID = "C38806164DD566333A92A410"
            } else if filePath.contains("Views/Dashboard") {
                groupUUID = "EA26B0E5D067B5922CF6F2C8"
            } else if filePath.contains("Views/Dev Tools") || filePath.contains("Dev Tools") {
                groupUUID = "2B4CEE860D734A23837F5302"
            } else if filePath.contains("Views") {
                groupUUID = "FE18E54E76741F54A82CD586"
            } else if filePath.contains("Utilities") {
                groupUUID = "576E45E47FC5098A3A96ECB8"
            } else if filePath.contains("Backend/AI") {
                groupUUID = "DF6B1A5F79682983F71C7E7E"
            } else if filePath.contains("Backend/Git") {
                groupUUID = "E063E218D13ACDDD0B728F8D"
            } else if filePath.contains("Persistence/Templates") {
                groupUUID = "265E9A432B28B39C005F9A10"
            } else if filePath.contains("Models") {
                groupUUID = "2B21AC80A9DC86CB7D9BD14F"
            } else if filePath.contains("Services") {
                groupUUID = "57AFC04E569B8BDE2658ECD4"
            } else if filePath.contains("GitHub") {
                groupUUID = "718173758FBD56C156A0D0F5"
            } else if filePath.contains("UI/Styles/Styling") {
                groupUUID = "B0020001B0020001B0020001"
            } else {
                groupUUID = "DA941B6FA862048858B975DF" // Fallback to Core/AI
            }

            // 1. Add to PBXBuildFile section
            let buildFileEntry = "\t\t\(buildFileId) /* \(fileName) in Sources */ = {isa = PBXBuildFile; fileRef = \(fileId) /* \(fileName) */; };\n"
            if let buildFileRange = updated.range(of: "/* Begin PBXBuildFile section */") {
                updated.insert(contentsOf: buildFileEntry, at: buildFileRange.upperBound)
            } else {
                return .failure("PBXBuildFile section not found")
            }

            // 2. Add to PBXFileReference section
            let fileRefEntry = "\t\t\(fileId) /* \(fileName) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"\(filePath)\"; sourceTree = SOURCE_ROOT; };\n"
            if let fileRefRange = updated.range(of: "/* Begin PBXFileReference section */") {
                updated.insert(contentsOf: fileRefEntry, at: fileRefRange.upperBound)
            } else {
                return .failure("PBXFileReference section not found")
            }

            // 3. Add to target group's children array
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

            // 4. Add to Sources Build Phase
            let sourcesPhaseStr = "9BF8BFB9B87ED46BDA700029 /* Sources */ = {"
            if let phaseIndex = updated.range(of: sourcesPhaseStr) {
                let searchRange = phaseIndex.lowerBound..<updated.endIndex
                if let filesRange = updated.range(of: "files = (\n", options: [], range: searchRange) {
                    let filesEntry = "\t\t\t\t\(buildFileId) /* \(fileName) in Sources */,\n"
                    updated.insert(contentsOf: filesEntry, at: filesRange.upperBound)
                } else {
                    return .failure("files block not found in Sources build phase")
                }
            } else {
                return .failure("Sources build phase 9BF8BFB9B87ED46BDA700029 not found")
            }

            try context.fileSystem.writeFile(at: pbxPath, content: updated)
            return .success("Project mutation complete: added \(fileName) via 4-step registration protocol", data: ["project": pbxPath])

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

    private func generateRandomHexID() -> String {
        let chars = Array("0123456789ABCDEF")
        return String((0..<24).compactMap { _ in chars.randomElement() })
    }
}
