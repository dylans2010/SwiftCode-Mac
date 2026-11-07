import Foundation

public struct AssistGitBranchCompareTool: AssistTool {
    public let id = "git_branch_compare"
    public let name = "Compare Branches"
    public let description = "Compares two branches with diff stat plus the commits in head not in base."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Compares two branches with diff stat plus the commits in head not in base.",
            properties: [
                "base": JSONSchema(type: "string", description: "Base branch or ref."),
                "head": JSONSchema(type: "string", description: "Head branch or ref.")
            ],
            required: ["base", "head"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let baseRaw = (input["base"] as? String) else {
            return .failure("Missing required parameter: base")
        }
        guard let headRaw = (input["head"] as? String) else {
            return .failure("Missing required parameter: head")
        }
        let base = baseRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = headRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            return .failure("Missing required parameter: base")
        }
        guard !head.isEmpty else {
            return .failure("Missing required parameter: head")
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

        let commits = logResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitLines = commits.isEmpty ? [] : commits.components(separatedBy: "\n")
        let stat = statResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitSection = commitLines.isEmpty ? "No commits in \(head) not in \(base)." : commitLines.joined(separator: "\n")
        let statSection = stat.isEmpty ? "No differences." : stat
        let output = "Branch comparison \(base)...\(head)\n\nCommits in \(head) not in \(base) (\(commitLines.count)):\n\(commitSection)\n\nDiff stat:\n\(statSection)"
        return .success(output, data: ["base": base, "head": head, "commits": commits, "diffStat": stat, "commitCount": "\(commitLines.count)"])
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
