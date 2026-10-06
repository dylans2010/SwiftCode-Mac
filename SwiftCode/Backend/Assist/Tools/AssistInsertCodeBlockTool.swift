import Foundation

public struct AssistInsertCodeBlockTool: AssistTool {
    public let id = "code_insert"
    public let name = "Insert Code Block"
    public let description = "Inserts a block of code at a specific line or before/after a symbol."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Inserts a block of code at a line number or before/after a symbol pattern.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the file to modify."),
                "code": JSONSchema(type: "string", description: "Code block to insert."),
                "mode": JSONSchema(type: "string", description: "One of 'line', 'before', or 'after'. Default: \"line\"."),
                "line": JSONSchema(type: "string", description: "1-based line number for 'line' mode. Appends past end of file. Default: \"1\"."),
                "pattern": JSONSchema(type: "string", description: "Anchor text for 'before'/'after' modes. Required in those modes.")
            ],
            required: ["path", "code"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        guard let code = input["code"] as? String else {
            return .failure("Missing required parameter: code")
        }

        do {
            let content = try context.fileSystem.readFile(at: path)
            LiveDiffStreamer.shared.beginEdit(
                filePath: path,
                operationType: .insert,
                beforeContent: content
            )

            let insertionMode = (input["mode"] as? String ?? "line").lowercased()
            let updated: String

            switch insertionMode {
            case "before":
                guard let pattern = input["pattern"] as? String else {
                    LiveDiffStreamer.shared.cancelStream(filePath: path)
                    return .failure("Missing required parameter for before mode: pattern")
                }
                updated = AssistCodeFunctions.insertBefore(in: content, pattern: pattern, insert: code)
            case "after":
                guard let pattern = input["pattern"] as? String else {
                    LiveDiffStreamer.shared.cancelStream(filePath: path)
                    return .failure("Missing required parameter for after mode: pattern")
                }
                updated = AssistCodeFunctions.insertAfter(in: content, pattern: pattern, insert: code)
            default:
                let lineNumber = max(1, Int(input["line"] as? String ?? "1") ?? 1)
                var lines = content.components(separatedBy: .newlines)
                let insertIndex = min(lineNumber - 1, lines.count)
                lines.insert(contentsOf: code.components(separatedBy: .newlines), at: insertIndex)
                updated = lines.joined(separator: "\n")
            }

            LiveDiffStreamer.shared.streamMutation(filePath: path, currentContent: updated, isFinal: false)
            try context.fileSystem.writeFile(at: path, content: updated)
            LiveDiffStreamer.shared.completeEdit(filePath: path, finalContent: updated)

            return .success("Code block inserted into \(path)")
        } catch {
            LiveDiffStreamer.shared.cancelStream(filePath: path)
            return .failure("Failed to insert code into \(path): \(error.localizedDescription)")
        }
    }
}
