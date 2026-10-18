//
//  AssistGitLogViewerTool.swift
//  SwiftCode
//

import Foundation

public struct AssistGitLogViewerTool: AssistTool {
    public let id = "git_log_viewer"
    public let name = "Git Log Viewer"
    public let description = "Retrieves structured commit history, commit hashes, dates, authors, and changed file stats."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Fetches recent Git commit history with author and message details.",
            properties: [
                "maxCount": JSONSchema(type: "integer", description: "Maximum number of commits to retrieve (default: 15)."),
                "path": JSONSchema(type: "string", description: "Optional specific file or directory path to filter log history for.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let maxCount = (input["maxCount"] as? Int) ?? 15
        let path = input["path"] as? String

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        var args = ["log", "-n", "\(maxCount)", "--pretty=format:%h | %an | %ad | %s", "--date=short"]
        if let p = path, !p.isEmpty {
            args.append("--")
            args.append(p)
        }
        proc.arguments = args
        proc.currentDirectoryURL = context.workspaceRoot

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if proc.terminationStatus != 0 {
                return .failure("git log failed: \(out)")
            }

            if out.isEmpty {
                return .success("No commits found in the repository history.")
            }

            let lines = out.components(separatedBy: .newlines)
            var report = "### Recent Git Commits (\(lines.count) entries):\n\n"
            for l in lines {
                report += "- `\(l)`\n"
            }
            return .success(report)
        } catch {
            return .failure("Failed to execute git log: \(error.localizedDescription)")
        }
    }
}
