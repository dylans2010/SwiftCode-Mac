import Foundation

public struct AssistReplaceInFileTool: AssistTool {
    public let id = "code_replace"
    public let name = "Replace in File"
    public let description = "Replaces a specific targeted code snippet within an existing file, ensuring exact match and providing unified diffs."
    public let capability: ToolCapability = .fileModification
    public let riskLevel: ToolRiskLevel = .safeMutation

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Replaces occurrences of a targeted code block with a replacement.",
            properties: [
                "path": JSONSchema(type: "string", description: "The relative path to the file to modify."),
                "target": JSONSchema(type: "string", description: "The exact existing text snippet to find and replace."),
                "replacement": JSONSchema(type: "string", description: "The new text snippet to insert in place of the target."),
                "allowMultiple": JSONSchema(type: "boolean", description: "Whether to replace multiple occurrences if found (default false).")
            ],
            required: ["path", "target", "replacement"]
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: 'path'")
        }
        guard let target = input["target"] as? String else {
            return .failure("Missing required parameter: 'target'")
        }
        guard let replacement = input["replacement"] as? String else {
            return .failure("Missing required parameter: 'replacement'")
        }
        let allowMultiple = input["allowMultiple"] as? Bool ?? false

        // Sandbox & Traversal Defense
        if path.contains("..") || path.hasPrefix("/") {
            return .failure("Path security error: Relative path traversal ('..') and absolute paths are prohibited for safety. Path: '\(path)'")
        }

        let startTime = Date()
        do {
            let original = try context.fileSystem.readFile(at: path)

            // Live Diff Streamer: Broadcast edit initiation
            LiveDiffStreamer.shared.beginEdit(
                filePath: path,
                operationType: .replace,
                beforeContent: original
            )

            // Execute verified targeted replacement with strict conflict checking
            let modified = try AssistDiffEngine.shared.applyTargetedReplacement(
                source: original,
                target: target,
                replacement: replacement,
                allowMultiple: allowMultiple,
                filePath: path
            )

            // Live Diff Streamer: Stream in-flight mutation state
            LiveDiffStreamer.shared.streamMutation(
                filePath: path,
                currentContent: modified,
                isFinal: false
            )

            // Save modified content
            try context.fileSystem.writeFile(at: path, content: modified)

            // Complete in-flight diff stream
            LiveDiffStreamer.shared.completeEdit(filePath: path, finalContent: modified)

            // Reconcile with verified disk state
            if let verifiedDisk = try? context.fileSystem.readFile(at: path) {
                LiveDiffStreamer.shared.reconcileWithDisk(filePath: path, actualDiskContent: verifiedDisk)
            }

            // Generate unified diff via Myers algorithm
            let diff = AssistDiffEngine.shared.generateUnifiedDiff(
                filePath: path,
                original: original,
                modified: modified
            )

            var suggestedActions: [String] = ["project_build"]
            if path.hasSuffix(".swift") {
                suggestedActions.insert("syntax_verify", at: 0)
            }

            let duration = Date().timeIntervalSince(startTime)

            return AssistToolResult(
                success: true,
                output: "Successfully updated \(path) with targeted replacement.\n\nUnified Diff:\n\(diff)",
                data: [
                    AssistToolDataKey.diff: diff,
                    "path": path
                ],
                diagnostics: [],
                filesChanged: [path],
                diff: diff,
                duration: duration,
                suggestedNextActions: suggestedActions,
                beforeContent: original,
                afterContent: modified
            )
        } catch let conflict as DiffConflictError {
            LiveDiffStreamer.shared.cancelStream(filePath: path)
            switch conflict {
            case .targetNotFound(let snippet, let file):
                return .failure("Target snippet not found in '\(file)'. Please re-read the file with 'file_read' to inspect the exact existing lines before attempting replacement. Target snippet was: '\(snippet)'")
            case .multipleMatches(let snippet, let count, let file):
                return .failure("Target snippet matched \(count) times in '\(file)'. Provide more surrounding lines to uniquely identify the location, or pass 'allowMultiple: true'. Snippet was: '\(snippet)'")
            case .staleFileState(let file):
                return .failure("File '\(file)' state changed unexpectedly on disk during operation.")
            }
        } catch {
            LiveDiffStreamer.shared.cancelStream(filePath: path)
            return .failure("Failed to replace in file at \(path): \(error.localizedDescription)")
        }
    }
}
