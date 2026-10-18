import Foundation

public struct AssistGitCherryPickTool: AssistTool {
    public let id = "git_cherry_pick"
    public let name = "Git Cherry-Pick"
    public let description = "Cherry-picks one commit onto the current branch. On conflict it reports the conflicted files and leaves the state for manual resolution."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Cherry-picks one commit onto the current branch.",
            properties: [
                "commit": JSONSchema(type: "string", description: "Full or short commit SHA, or a validated ref to cherry-pick."),
                "noCommit": JSONSchema(type: "string", description: "Pass \"true\" to stage the change without committing (--no-commit). Default: false.")
            ],
            required: ["commit"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let commitRaw = (input["commit"] as? String) else {
            return .failure("Missing required parameter: commit")
        }
        let commit = commitRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commit.isEmpty else {
            return .failure("Missing required parameter: commit")
        }
        guard isValidCommit(commit) else {
            return .failure("Invalid commit: \(commit)")
        }

        var args = ["cherry-pick"]
        if boolValue(input["noCommit"]) {
            args.append("--no-commit")
        }
        args.append(commit)

        let result = runGit(args: args, cwd: context.workspaceRoot)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0 else {
            let conflicted = conflictedFiles(cwd: context.workspaceRoot)
            if !conflicted.isEmpty {
                return .failure("Cherry-pick of \(commit) stopped due to conflicts in: \(conflicted.joined(separator: ", ")). Resolve the conflicts and commit, or run git cherry-pick --abort. Git output: \(output)")
            }
            return .failure("Git cherry-pick failed: \(output.isEmpty ? "unknown error" : output)")
        }
        let display = output.isEmpty ? "Cherry-pick completed with no output." : output
        return .success("Cherry-picked \(commit).\n\(display)", data: ["commit": commit, "output": output])
    }

    private func conflictedFiles(cwd: URL) -> [String] {
        let status = runGit(args: ["status", "--porcelain"], cwd: cwd)
        guard status.status == 0 else { return [] }
        let conflictCodes: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        var files: [String] = []
        for line in status.output.components(separatedBy: "\n") {
            guard line.count >= 3 else { continue }
            let code = String(line.prefix(2))
            guard conflictCodes.contains(code) else { continue }
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if !path.isEmpty {
                files.append(path)
            }
        }
        return files
    }

    private func isValidCommit(_ value: String) -> Bool {
        if value.hasPrefix("-") { return false }
        if value.contains("\0") || value.contains("\n") || value.contains("\r") { return false }
        if isSHA(value) { return true }
        return isValidRef(value)
    }

    private func isSHA(_ value: String) -> Bool {
        guard value.count >= 7, value.count <= 40 else { return false }
        return value.allSatisfy { $0.isHexDigit }
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

    private func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let s = value as? String {
            let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lowered == "true" || lowered == "1" || lowered == "yes"
        }
        return false
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
