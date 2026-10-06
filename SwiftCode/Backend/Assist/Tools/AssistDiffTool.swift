import Foundation

public struct AssistDiffTool: AssistTool {
    public let id = "project_diff"
    public let name = "Diff Project"
    public let description = "Compares the working tree with Git HEAD, returning real unified diffs and modified files."
    public let capability: ToolCapability = .gitOperations
    public let riskLevel: ToolRiskLevel = .safeRead

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Compares working tree with Git HEAD, returning unified diff.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional file path to constrain diff scope.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let startTime = Date()
        do {
            let status = try await GitService.shared.getStatus(for: context.workspaceRoot)
            let diffHunks = try await GitService.shared.getDiff(repositoryURL: context.workspaceRoot)

            var modifiedFiles: [String] = []
            for item in status.files {
                modifiedFiles.append(item.path.lastPathComponent)
            }

            if diffHunks.isEmpty && modifiedFiles.isEmpty {
                return AssistToolResult(
                    success: true,
                    output: "No changes detected. Working tree is clean.",
                    data: [AssistToolDataKey.diff: ""],
                    filesChanged: [],
                    diff: "",
                    duration: Date().timeIntervalSince(startTime),
                    suggestedNextActions: ["project_build", "code_review"]
                )
            }

            let formattedDiff = diffHunks.map { hunk in
                "\(hunk.header)\n\(hunk.lines.joined(separator: "\n"))"
            }.joined(separator: "\n\n")

            let summary = "Git Status on branch '\(status.branchName)': \(status.stagedFiles.count) staged, \(status.unstagedFiles.count) unstaged, \(diffHunks.count) diff hunks."

            return AssistToolResult(
                success: true,
                output: "\(summary)\n\n\(formattedDiff)",
                data: [
                    AssistToolDataKey.diff: formattedDiff,
                    "branch": status.branchName,
                    "staged_count": "\(status.stagedFiles.count)",
                    "unstaged_count": "\(status.unstagedFiles.count)"
                ],
                diagnostics: [],
                filesChanged: modifiedFiles,
                diff: formattedDiff,
                duration: Date().timeIntervalSince(startTime),
                suggestedNextActions: ["project_build", "code_review"]
            )
        } catch {
            return .failure("Diff inspection failed: \(error.localizedDescription)")
        }
    }
}
