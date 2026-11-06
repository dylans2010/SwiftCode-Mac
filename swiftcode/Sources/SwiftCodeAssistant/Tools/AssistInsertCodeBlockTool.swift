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
            description: "Inserts a block of code at a line number or before/after a symbol pattern. Pattern misses are failures, never silent no-ops.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the file to modify."),
                "code": JSONSchema(type: "string", description: "Code block to insert."),
                "mode": JSONSchema(type: "string", description: "One of 'line', 'before', or 'after'. Default: \"line\". Unknown modes are rejected."),
                "line": JSONSchema(type: "integer", description: "1-based line number for 'line' mode. Appends past end of file. Default: 1."),
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

        // Validate mode / pattern / line BEFORE opening a diff stream or
        // touching the file, so a rejected call leaves no partial state.
        let insertionMode = (input["mode"] as? String ?? "line").lowercased()
        guard ["line", "before", "after"].contains(insertionMode) else {
            return .failure("Unknown mode '\(insertionMode)': expected 'line', 'before', or 'after'.")
        }
        var pattern: String?
        if insertionMode == "before" || insertionMode == "after" {
            guard let p = input["pattern"] as? String, !p.isEmpty else {
                return .failure("Missing required parameter for \(insertionMode) mode: pattern")
            }
            pattern = p
        }
        var lineNumber = 1
        if insertionMode == "line" {
            if let rawLine = input["line"] {
                guard let parsed = Self.parseLineNumber(rawLine) else {
                    return .failure("Invalid line: must be an integer >= 1 (got '\(rawLine)').")
                }
                lineNumber = parsed
            }
        }

        do {
            let content = try context.fileSystem.readFile(at: path)
            // Pattern modes must actually match; the helpers return the
            // original content unchanged on a miss, which previously
            // reported success while writing an unchanged file.
            if let pattern {
                guard content.contains(pattern) else {
                    return .failure("Pattern not found in \(path): '\(pattern)'. No changes made.")
                }
            }

            LiveDiffStreamer.shared.beginEdit(
                filePath: path,
                operationType: .insert,
                beforeContent: content
            )

            let updated: String
            switch insertionMode {
            case "before":
                updated = AssistCodeFunctions.insertBefore(in: content, pattern: pattern!, insert: code)
            case "after":
                updated = AssistCodeFunctions.insertAfter(in: content, pattern: pattern!, insert: code)
            default:
                var lines = content.components(separatedBy: .newlines)
                let insertIndex = min(lineNumber - 1, lines.count)
                lines.insert(contentsOf: code.components(separatedBy: .newlines), at: insertIndex)
                updated = lines.joined(separator: "\n")
            }

            guard updated != content else {
                LiveDiffStreamer.shared.cancelStream(filePath: path)
                return .failure("Insert made no change to \(path). No changes made.")
            }

            LiveDiffStreamer.shared.streamMutation(filePath: path, currentContent: updated, isFinal: false)
            try context.fileSystem.writeFile(at: path, content: updated)
            LiveDiffStreamer.shared.completeEdit(filePath: path, finalContent: updated)

            let origCount = content.components(separatedBy: .newlines).count
            let newCount = updated.components(separatedBy: .newlines).count
            let addedLines = max(0, newCount - origCount)
            await MainActor.run {
                ProjectSessionStore.shared.recordAssistFileMutation(
                    path: path,
                    beforeContent: content,
                    afterContent: updated,
                    addedLines: addedLines > 0 ? addedLines : 1,
                    deletedLines: 0
                )
            }

            return .success("Code block inserted into \(path)", data: ["path": path], filesChanged: [path])
        } catch {
            LiveDiffStreamer.shared.cancelStream(filePath: path)
            return .failure("Failed to insert code into \(path): \(error.localizedDescription)")
        }
    }

    private static func parseLineNumber(_ value: Any) -> Int? {
        if let i = value as? Int, i >= 1 { return i }
        if let d = value as? Double, d >= 1, d == d.rounded(), d <= Double(Int.max) { return Int(d) }
        if let s = value as? String, let i = Int(s.trimmingCharacters(in: .whitespaces)), i >= 1 { return i }
        return nil
    }
}
