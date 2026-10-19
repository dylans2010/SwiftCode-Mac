import Foundation

public struct AssistCreateFileTool: AssistTool {
    public let id = "file_create"
    public let name = "Create File"
    public let description = "Creates a new file with full content and intermediate directories when needed."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Creates a new file with full content, creating intermediate directories when needed.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the file to create. Must be non-blank."),
                "content": JSONSchema(type: "string", description: "File body. Default: \"\"."),
                "overwrite": JSONSchema(type: "boolean", description: "Must be true to replace an existing file. Default: false.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: path", code: .missingArgument)
        }

        let content = input["content"] as? String ?? ""
        let overwrite = input["overwrite"] as? Bool ?? false

        if context.fileSystem.exists(at: path) && !overwrite {
            return .failure("File already exists at \(path). Set overwrite=true to replace it.", code: .invalidInput)
        }

        do {
            let fileURL = URL(fileURLWithPath: path)
            let dirPath = fileURL.deletingLastPathComponent().path
            if !dirPath.isEmpty, dirPath != ".", !context.fileSystem.exists(at: dirPath) {
                try context.fileSystem.createDirectory(at: dirPath)
            }

            // Live Diff Streamer: Broadcast edit initiation
            LiveDiffStreamer.shared.beginEdit(
                filePath: path,
                operationType: .create,
                beforeContent: ""
            )

            LiveDiffStreamer.shared.streamMutation(
                filePath: path,
                currentContent: content,
                isFinal: false
            )

            // Write updated content
            try context.fileSystem.writeFile(at: path, content: content)

            // Auto-register new file on Xcode project.pbxproj
            _ = try? XcodeProjWriter.shared.addFileReference(filePath: path, projectURL: context.workspaceRoot)

            LiveDiffStreamer.shared.completeEdit(filePath: path, finalContent: content)

            if let verifiedDisk = try? context.fileSystem.readFile(at: path) {
                LiveDiffStreamer.shared.reconcileWithDisk(filePath: path, actualDiskContent: verifiedDisk)
            }

            let diff = AssistDiffEngine.shared.generateUnifiedDiff(
                filePath: path,
                original: "",
                modified: content
            )

            let newCount = content.components(separatedBy: .newlines).count
            await MainActor.run {
                ProjectSessionStore.shared.recordAssistFileMutation(
                    path: path,
                    beforeContent: "",
                    afterContent: content,
                    addedLines: newCount,
                    deletedLines: 0
                )
            }

            return AssistToolResult(
                success: true,
                output: "Created file at \(path) (\(content.components(separatedBy: .newlines).count) lines)",
                data: [
                    "path": path,
                    "bytes": String(content.utf8.count),
                    AssistToolDataKey.diff: diff,
                    "is_new": "true"
                ],
                diagnostics: [],
                filesChanged: [path],
                diff: diff,
                duration: 0.1,
                suggestedNextActions: ["project_build"],
                beforeContent: "",
                afterContent: content
            )
        } catch {
            LiveDiffStreamer.shared.cancelStream(filePath: path)
            return .failure("Failed to create file at \(path): \(error.localizedDescription)", code: .executionFailed)
        }
    }
}
