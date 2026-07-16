import Foundation

public struct AssistMultiFileEditTool: AssistTool {
    public let id = "code_multi_edit"
    public let name = "Multi-file Edit"
    public let description = "Applies edits across multiple files simultaneously."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let edits = input["edits"] as? [[String: String]] else {
            return .failure("Missing required parameter: edits")
        }

        var updatedPaths: [String] = []
        for edit in edits {
            guard let path = edit["path"] else { continue }
            do {
                if let content = edit["content"] {
                    try context.fileSystem.writeFile(at: path, content: content)
                } else {
                    let original = try context.fileSystem.readFile(at: path)
                    let search = edit["search"] ?? ""
                    let replace = edit["replace"] ?? ""
                    let updated = AssistCodeFunctions.replaceBlock(in: original, search: search, replace: replace)
                    try context.fileSystem.writeFile(at: path, content: updated)
                }
                updatedPaths.append(path)
            } catch {
                return .failure("Failed to apply edit to \(path): \(error.localizedDescription)")
            }
        }

        return .success("Multi-file edit completed for \(updatedPaths.count) files", data: ["files": updatedPaths.joined(separator: ",")])
    }
}
