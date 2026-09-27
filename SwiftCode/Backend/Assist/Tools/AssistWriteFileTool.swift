import Foundation

public struct AssistWriteFileTool: AssistTool {
    public let id = "file_write"
    public let name = "Write File"
    public let description = "Writes or overwrites a file with the specified content, generating unified diffs."
    public let capability: ToolCapability = .fileModification
    public let riskLevel: ToolRiskLevel = .safeMutation

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Writes or overwrites a file with the specified content.",
            properties: [
                "path": JSONSchema(type: "string", description: "The relative path to write the file within the project workspace."),
                "content": JSONSchema(type: "string", description: "The complete content to write into the file.")
            ],
            required: ["path", "content"]
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String, let content = input["content"] as? String else {
            return .failure("Missing required parameters: 'path' and 'content' are mandatory.")
        }

        // Sandbox & Traversal Defense
        if path.contains("..") || path.hasPrefix("/") {
            return .failure("Path security error: Relative path traversal ('..') and absolute paths are prohibited for safety. Path: '\(path)'")
        }

        let startTime = Date()
        do {
            let isNewFile = !context.fileSystem.exists(at: path)
            let originalContent = isNewFile ? "" : (try? context.fileSystem.readFile(at: path)) ?? ""

            // Write updated content
            try context.fileSystem.writeFile(at: path, content: content)

            // Generate verified Unified Diff
            let diff = AssistDiffEngine.shared.generateUnifiedDiff(
                filePath: path,
                original: originalContent,
                modified: content
            )

            var suggestedActions: [String] = ["project_build"]
            if path.hasSuffix(".swift") {
                suggestedActions.insert("syntax_verify", at: 0)
            }

            let duration = Date().timeIntervalSince(startTime)
            let statusText = isNewFile ? "Created new file" : "Updated existing file"

            return AssistToolResult(
                success: true,
                output: "\(statusText): \(path) (\(content.components(separatedBy: .newlines).count) lines)",
                data: [
                    AssistToolDataKey.diff: diff,
                    "path": path,
                    "is_new": isNewFile ? "true" : "false"
                ],
                diagnostics: [],
                filesChanged: [path],
                diff: diff,
                duration: duration,
                suggestedNextActions: suggestedActions,
                beforeContent: originalContent,
                afterContent: content
            )
        } catch {
            return .failure("Failed to write file at \(path): \(error.localizedDescription)")
        }
    }
}
