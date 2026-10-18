import Foundation

public struct AssistSessionExportTool: AssistTool {
    public let id = "session_export"
    public let name = "Export Session"
    public let description = "Writes a markdown export with session metadata (title, timestamp, session ID, workspace, notes). Does not read conversation history. Refuses to overwrite unless overwrite is true."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Exports session metadata to a markdown file.",
            properties: [
                "title": JSONSchema(type: "string", description: "Export title (optional)."),
                "notes": JSONSchema(type: "string", description: "Free-form notes to include (optional)."),
                "outputPath": JSONSchema(type: "string", description: "Workspace-relative output path. Default is .assist_session_export.md."),
                "overwrite": JSONSchema(type: "string", description: "Set to true to overwrite an existing output file. Default is false.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let rawOutput = (input["outputPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputRelative = (rawOutput?.isEmpty == false) ? rawOutput! : ".assist_session_export.md"
        guard let outputURL = resolveInsideWorkspace(outputRelative, workspaceRoot: context.workspaceRoot) else {
            return .failure("Invalid outputPath: '\(outputRelative)' must be a workspace-relative path without '..' and must stay inside the workspace.")
        }
        let overwrite = ((input["overwrite"] as? String) ?? "").lowercased() == "true"
        if FileManager.default.fileExists(atPath: outputURL.path) && !overwrite {
            return .failure("Refusing to overwrite existing file at '\(outputRelative)'. Pass overwrite=true to replace it.")
        }
        let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = (title?.isEmpty == false) ? title! : "Assist Session Export"
        let notes = (input["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())

        var markdown = "# \(effectiveTitle)\n\n"
        markdown += "- Exported: \(timestamp)\n"
        markdown += "- Session ID: \(context.sessionId.uuidString)\n"
        markdown += "- Workspace: \(context.workspaceRoot.path)\n\n"
        markdown += "## Tool Registry\n\n"
        markdown += "Tool definitions live in AssistToolRegistry. This export contains session metadata only.\n\n"
        markdown += "## Notes\n\n"
        markdown += notes.isEmpty ? "_No notes provided._\n" : notes + "\n"
        // Deliberately no conversation-history access: this tool exports
        // metadata supplied in its inputs plus the session context only.

        do {
            try markdown.data(using: .utf8)?.write(to: outputURL, options: [.atomic])
        } catch {
            return .failure("Failed to write session export to '\(outputRelative)': \(error.localizedDescription)")
        }
        return .success("Session export written to \(outputRelative) (session \(context.sessionId.uuidString)).", data: [
            "output_path": outputURL.path,
            "output_relative": outputRelative,
            "session_id": context.sessionId.uuidString,
            "timestamp": timestamp
        ])
    }

    private func resolveInsideWorkspace(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(separator: "/").map(String.init)
        if components.contains("..") { return nil }
        if trimmed.hasPrefix("/") {
            guard trimmed == workspaceRoot.path || trimmed.hasPrefix(workspaceRoot.path + "/") else { return nil }
            return URL(fileURLWithPath: trimmed)
        }
        return workspaceRoot.appendingPathComponent(trimmed)
    }
}
