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
        guard var path = (input["path"] ?? input["filePath"] ?? input["file_path"]) as? String,
              let content = (input["content"] ?? input["fileContent"] ?? input["file_content"] ?? input["code"]) as? String else {
            return .failure("Missing required parameters: 'path' and 'content' are mandatory.")
        }

        // Sandbox & Traversal Defense: Normalize workspace path
        let workspacePrefix = context.workspaceRoot.path
        if !workspacePrefix.isEmpty && path.hasPrefix(workspacePrefix) {
            path = String(path.dropFirst(workspacePrefix.count))
        }
        while path.hasPrefix("/") {
            path = String(path.dropFirst())
        }

        if path.contains("..") {
            return .failure("Path security error: Relative path traversal ('..') is prohibited for safety. Path: '\(path)'")
        }

        let startTime = Date()
        do {
            let isNewFile = !context.fileSystem.exists(at: path)
            let originalContent = isNewFile ? "" : (try? context.fileSystem.readFile(at: path)) ?? ""

            // Live Diff Streamer: Broadcast edit initiation
            LiveDiffStreamer.shared.beginEdit(
                filePath: path,
                operationType: isNewFile ? .create : .write,
                beforeContent: originalContent
            )

            // Live Diff Streamer: Stream in-flight mutation state
            LiveDiffStreamer.shared.streamMutation(
                filePath: path,
                currentContent: content,
                isFinal: false
            )

            // Write updated content
            try context.fileSystem.writeFile(at: path, content: content)

            // Complete in-flight diff stream
            LiveDiffStreamer.shared.completeEdit(filePath: path, finalContent: content)

            // Reconcile with verified disk state
            if let verifiedDisk = try? context.fileSystem.readFile(at: path) {
                LiveDiffStreamer.shared.reconcileWithDisk(filePath: path, actualDiskContent: verifiedDisk)
            }

            // Generate verified Unified Diff via Myers algorithm
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
            LiveDiffStreamer.shared.cancelStream(filePath: path)
            return .failure("Failed to write file at \(path): \(error.localizedDescription)")
        }
    }
}
