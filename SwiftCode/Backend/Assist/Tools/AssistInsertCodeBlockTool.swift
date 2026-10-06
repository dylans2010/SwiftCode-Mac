import Foundation

public struct AssistInsertCodeBlockTool: AssistTool {
    public let id = "code_insert"
    public let name = "Insert Code Block"
    public let description = "Inserts a block of code at a specific line or before/after a symbol."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Inserts a block of code at a specific line or relative to a pattern.",
            properties: [
                "path": JSONSchema(type: "string", description: "The relative path of the target file."),
                "code": JSONSchema(type: "string", description: "The code block snippet to insert."),
                "mode": JSONSchema(type: "string", description: "Insertion mode (e.g., 'afterPattern', 'beforePattern', 'atLine')."),
                "pattern": JSONSchema(type: "string", description: "Target pattern string for matching location."),
                "line": JSONSchema(type: "integer", description: "1-based line number for line-based insertion.")
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
