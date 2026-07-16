import Foundation

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
        case "add":
            guard let file = input["filePath"] as? String else { return .failure("Missing filePath") }
            if updated.contains(file) { return .success("File already referenced: \(file)") }
            let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24)).uppercased()
            let entry = "\t\t\(id) /* \((file as NSString).lastPathComponent) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"\(file)\"; sourceTree = SOURCE_ROOT; };"
            if let range = updated.range(of: "/* End PBXFileReference section */") {
                updated.insert(contentsOf: entry + "\n", at: range.lowerBound)
            }
        case "remove":
            guard let file = input["filePath"] as? String else { return .failure("Missing filePath") }
            updated = updated
                .components(separatedBy: .newlines)
                .filter { !$0.contains(file) }
                .joined(separator: "\n")
        default:
            return .failure("Unsupported action: \(action)")
        }

        try context.fileSystem.writeFile(at: pbxPath, content: updated)
        return .success("Project mutation complete: \(action)", data: ["project": pbxPath])
    }
}
