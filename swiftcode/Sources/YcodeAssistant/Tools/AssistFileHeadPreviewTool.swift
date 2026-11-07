import Foundation

public struct AssistFileHeadPreviewTool: AssistTool {
    public let id = "file_head_preview"
    public let name = "File Head Preview"
    public let description = "Previews the first N lines of a file with encoding detection. Never dumps whole files."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Previews the head of a file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative file path."),
                "lines": JSONSchema(type: "integer", description: "Lines to preview. Default 20, max 100.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        let n = max(1, min(100, (input["lines"] as? Int) ?? 20))
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(raw)")
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure("Cannot read file: \(raw)")
        }
        var encoding = "utf-8"
        var text: String? = String(data: data, encoding: .utf8)
        if text == nil {
            text = String(data: data, encoding: .utf16)
            if text != nil { encoding = "utf-16" }
        }
        if text == nil {
            text = String(data: data, encoding: .isoLatin1)
            if text != nil { encoding = "iso-latin-1" }
        }
        guard let content = text else {
            return .failure("File is not decodable text (likely binary): \(raw)")
        }
        let allLines = content.components(separatedBy: .newlines)
        let head = allLines.prefix(n)
        let numbered = head.enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        let truncated = allLines.count > n
        let output = "Preview of \(raw) [\(encoding), \(allLines.count) total lines]:\n\(numbered)" + (truncated ? "\n… [truncated: showing \(n) of \(allLines.count) lines]" : "")
        return .success(output, data: [
            "path": raw, "encoding": encoding,
            "totalLines": "\(allLines.count)", "shownLines": "\(min(n, allLines.count))",
            "truncated": truncated ? "true" : "false"
        ])
    }
}
