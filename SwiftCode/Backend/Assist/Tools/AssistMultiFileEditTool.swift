import Foundation

public struct AssistMultiFileEditTool: AssistTool {
    public let id = "code_multi_edit"
    public let name = "Multi-file Edit"
    public let description = "Applies edits across multiple files simultaneously."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Applies edits across multiple files. Not atomic: earlier edits persist if a later one fails; the failure names which edits were already applied. Each edit requires a non-empty 'path'. Search/replace edits require a non-empty 'search' (an empty search would corrupt the file).",
            properties: [
                "edits": JSONSchema(type: "array", description: "Array of edit objects. Each object requires a non-empty 'path', plus either 'content' (full-file replacement) or 'search' + 'replace'.")
            ],
            required: ["edits"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let edits = input["edits"] as? [[String: Any]] else {
            return .failure("Missing required parameter: edits (array of edit objects)")
        }

        // Validate every edit BEFORE applying any of them, so a malformed
        // entry fails fast instead of silently skipping an edit mid-batch.
        struct ValidatedEdit { let path: String; let content: String?; let search: String?; let replace: String? }
        var validated: [ValidatedEdit] = []
        for (index, edit) in edits.enumerated() {
            guard let path = edit["path"] as? String, !path.isEmpty else {
                return .failure("Edit #\(index + 1) is missing a non-empty 'path'. No edits were applied.")
            }
            if let content = edit["content"] as? String {
                validated.append(ValidatedEdit(path: path, content: content, search: nil, replace: nil))
            } else {
                guard let search = edit["search"] as? String, !search.isEmpty else {
                    return .failure("Edit #\(index + 1) for \(path) is missing a non-empty 'search'. No edits were applied.")
                }
                let replace = (edit["replace"] as? String) ?? ""
                validated.append(ValidatedEdit(path: path, content: nil, search: search, replace: replace))
            }
        }

        var updatedPaths: [String] = []
        for edit in validated {
            do {
                if let content = edit.content {
                    try context.fileSystem.writeFile(at: edit.path, content: content)
                } else {
                    let original = try context.fileSystem.readFile(at: edit.path)
                    guard original.contains(edit.search!) else {
                        return .failure("Search text not found in \(edit.path). Edits already applied: \(updatedPaths.joined(separator: ", ")).")
                    }
                    let updated = AssistCodeFunctions.replaceBlock(in: original, search: edit.search!, replace: edit.replace ?? "")
                    guard updated != original else {
                        return .failure("Edit for \(edit.path) made no change. Edits already applied: \(updatedPaths.joined(separator: ", ")).")
                    }
                    try context.fileSystem.writeFile(at: edit.path, content: updated)
                }
                updatedPaths.append(edit.path)
            } catch {
                return .failure("Failed to apply edit to \(edit.path): \(error.localizedDescription). Edits already applied: \(updatedPaths.joined(separator: ", ")).")
            }
        }

        return .success(
            "Multi-file edit completed for \(updatedPaths.count) files",
            data: ["files": updatedPaths.joined(separator: ",")],
            filesChanged: updatedPaths
        )
    }
}
