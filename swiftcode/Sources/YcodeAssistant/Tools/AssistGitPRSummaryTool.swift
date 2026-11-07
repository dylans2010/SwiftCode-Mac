import Foundation

public struct AssistGitPRSummaryTool: AssistTool {
    public let id = "git_pr_summary"
    public let name = "PR Summary"
    public let description = "Builds a local markdown PR summary (commits, files changed, insertions/deletions) for head versus base using only local git history. No network, no GitHub API."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Builds a local markdown PR summary for head versus base using only local git history.",
            properties: [
                "base": JSONSchema(type: "string", description: "Base branch or ref. Default: main."),
                "head": JSONSchema(type: "string", description: "Head branch or ref. Default: HEAD.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let baseRaw = (input["base"] as? String) ?? "main"
        let headRaw = (input["head"] as? String) ?? "HEAD"
        let base = baseRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = headRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            return .failure("Base ref must not be empty.")
        }
        guard !head.isEmpty else {
            return .failure("Head ref must not be empty.")
        }
        guard isValidRef(base) else {
            return .failure("Invalid git ref for base: \(base)")
        }
        guard isValidRef(head) else {
            return .failure("Invalid git ref for head: \(head)")
        }

        let logResult = runGit(args: ["log", "--oneline", "\(base)..\(head)"], cwd: context.workspaceRoot)
        guard logResult.status == 0 else {
            let detail = logResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure("Git log failed for \(base)..\(head): \(detail.isEmpty ? "unknown error" : detail)")
        }
        let statResult = runGit(args: ["diff", "--stat", "\(base)...\(head)"], cwd: context.workspaceRoot)
        guard statResult.status == 0 else {
            let detail = statResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure("Git diff failed for \(base)...\(head): \(detail.isEmpty ? "unknown error" : detail)")
        }
        let shortStatResult = runGit(args: ["diff", "--shortstat", "\(base)...\(head)"], cwd: context.workspaceRoot)
        let shortStat = shortStatResult.status == 0 ? shortStatResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let namesResult = runGit(args: ["diff", "--name-only", "\(base)...\(head)"], cwd: context.workspaceRoot)
        let changedFiles = namesResult.status == 0 ? namesResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let commits = logResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitLines = commits.isEmpty ? [] : commits.components(separatedBy: "\n")
        let fileLines = changedFiles.isEmpty ? [] : changedFiles.components(separatedBy: "\n")
        let filesChanged = numberBefore("file", in: shortStat)
        let insertions = numberBefore("insertion", in: shortStat)
        let deletions = numberBefore("deletion", in: shortStat)
        let fileCount = fileLines.isEmpty ? filesChanged : fileLines.count

        var lines: [String] = []
        lines.append("# PR Summary")
        lines.append("")
        lines.append("Base: `\(base)` → Head: `\(head)`")
        lines.append("")
        lines.append("## Commits (\(commitLines.count))")
        if commitLines.isEmpty {
            lines.append("No commits in \(head) not in \(base).")
        } else {
            for commit in commitLines {
                lines.append("- \(commit)")
            }
        }
        lines.append("")
        lines.append("## Files changed (\(fileCount))")
        if fileLines.isEmpty {
            lines.append("No files changed.")
        } else {
            for file in fileLines {
                lines.append("- `\(file)`")
            }
        }
        lines.append("")
        lines.append("## Stats")
        if shortStat.isEmpty {
            lines.append("No changes.")
        } else {
            lines.append(shortStat)
        }
        lines.append("")
        lines.append("Files changed: \(fileCount) | Insertions: \(insertions) | Deletions: \(deletions)")
        let summary = lines.joined(separator: "\n")
        return .success(summary, data: [
            "summary": summary,
            "base": base,
            "head": head,
            "commitCount": "\(commitLines.count)",
            "fileCount": "\(fileCount)",
            "insertions": "\(insertions)",
            "deletions": "\(deletions)",
            "shortstat": shortStat
        ])
    }

    private func numberBefore(_ marker: String, in text: String) -> Int {
        guard let range = text.range(of: marker) else { return 0 }
        let before = text[..<range.lowerBound]
        var digits = ""
        for ch in before.reversed() {
            if ch.isNumber {
                digits.insert(ch, at: digits.startIndex)
            } else if ch == " " || ch == "," {
                if !digits.isEmpty { break }
            } else {
                break
            }
        }
        return Int(digits) ?? 0
    }

    private func isValidRef(_ ref: String) -> Bool {
        guard !ref.isEmpty else { return false }
        if ref == "@" { return false }
        if ref.hasPrefix("-") { return false }
        if ref.contains("@{") { return false }
        if ref == "HEAD" { return true }
        if ref.hasPrefix("HEAD~") || ref.hasPrefix("HEAD^") {
            let tail = String(ref.dropFirst(4))
            var index = tail.startIndex
            while index < tail.endIndex {
                let marker = tail[index]
                guard marker == "~" || marker == "^" else { return false }
                index = tail.index(after: index)
                var digitCount = 0
                while index < tail.endIndex, tail[index].isNumber {
                    digitCount += 1
                    index = tail.index(after: index)
                }
                guard digitCount > 0 else { return false }
            }
            return true
        }
        let forbidden = [" ", ";", "&", "|", "`", "$", "(", ")", "<", ">", "\"", "'", "\\", "\n", "\r", "\t", "..", "~", "^", ":", "?", "*", "["]
        for item in forbidden {
            if ref.contains(item) { return false }
        }
        if ref.contains("\0") { return false }
        if ref.hasPrefix("/") || ref.hasSuffix("/") || ref.contains("//") { return false }
        return true
    }

    private func runGit(args: [String], cwd: URL) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (1, "Failed to launch git: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}
