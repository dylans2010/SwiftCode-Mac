import Foundation

public struct AssistVersionControlOperator: AssistTool {
    public let id = "version_control_operator"
    public let name = "Version Control Operator"
    public let description = "Performs branch, commit, rollback, and diff operations using git."

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Performs branch, commit, rollback, and diff operations using git.",
            properties: [
                "action": JSONSchema(type: "string", description: "The git action to perform: status, commit, branch, rollback, or diff. Unknown actions are rejected."),
                "message": JSONSchema(type: "string", description: "The commit message (used for commit action)."),
                "name": JSONSchema(type: "string", description: "The branch name (used for branch action)."),
                "ref": JSONSchema(type: "string", description: "The git ref to reset to (used for rollback action). Default: HEAD~1. Must match the strict ref pattern; shell metacharacters are rejected.")
            ],
            required: ["action"]
        )
    }

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .potentiallyDestructive }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        #if os(macOS)
        let action = (input["action"] as? String ?? "status").lowercased()
        let cwd = context.workspaceRoot.path

        switch action {
        case "commit":
            let message = input["message"] as? String ?? "Assist automated commit"
            _ = try runGit(args: ["add", "-A"], cwd: cwd)
            let result = try runGit(args: ["commit", "-m", message], cwd: cwd)
            guard result.status == 0 else {
                return .failure("Git commit failed: \(result.output)")
            }
            return .success("Git action executed: commit", data: ["output": result.output])

        case "branch":
            let name = input["name"] as? String ?? "assist/automation"
            guard isValidRefName(name) else {
                return .failure("Invalid branch name: \(name)")
            }
            let result = try runGit(args: ["checkout", "-b", name], cwd: cwd)
            guard result.status == 0 else {
                return .failure("Git branch checkout failed: \(result.output)")
            }
            return .success("Git action executed: branch", data: ["output": result.output])

        case "rollback":
            let ref = input["ref"] as? String ?? "HEAD~1"
            guard isValidRefName(ref) else {
                return .failure("Invalid git ref: \(ref)")
            }
            let result = try runGit(args: ["reset", "--hard", ref], cwd: cwd)
            guard result.status == 0 else {
                return .failure("Git rollback failed: \(result.output)")
            }
            return .success("Git action executed: rollback", data: ["output": result.output])

        case "diff":
            let result = try runGit(args: ["diff", "--", "."], cwd: cwd)
            guard result.status == 0 else {
                return .failure("Git diff failed: \(result.output)")
            }
            return .success("Git action executed: diff", data: ["output": result.output])

        case "status":
            let result = try runGit(args: ["status", "--short"], cwd: cwd)
            guard result.status == 0 else {
                return .failure("Git status failed: \(result.output)")
            }
            return .success("Git action executed: status", data: ["output": result.output])

        default:
            return .failure("Unknown git action '\(action)': expected status, commit, branch, rollback, or diff.")
        }
        #else
        return .failure("Version control operations require macOS runtime")
        #endif
    }

    #if os(macOS)
    private func isValidRefName(_ ref: String) -> Bool {
        // Strict allow-list: letters, digits, and a small set of git-safe
        // punctuation, plus the explicit HEAD~N / HEAD^N forms. The old
        // validator skipped ALL checks whenever the ref contained "HEAD~"
        // anywhere, so "HEAD~1; rm -rf …" passed validation.
        guard !ref.isEmpty, ref.count <= 256 else { return false }
        if ref == "HEAD" { return true }
        if let match = ref.range(of: #"^HEAD[~^]\d+$"#, options: .regularExpression), match == ref.startIndex..<ref.endIndex { return true }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/-"))
        guard ref.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard !ref.contains("..") else { return false }
        guard !ref.hasPrefix("/") && !ref.hasSuffix("/") && !ref.hasSuffix(".lock") else { return false }
        return true
    }

    private func runGit(args: [String], cwd: String) throws -> (status: Int32, output: String) {
        // Argument vector (no shell) + bounded timeout via the shared runner.
        let run = try AssistArgvRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: args,
            workingDirectory: URL(fileURLWithPath: cwd),
            timeout: 120
        )
        guard !run.timedOut else {
            throw NSError(domain: "GitTimeout", code: 124, userInfo: [NSLocalizedDescriptionKey: "git \(args.first ?? "") timed out after 120s"])
        }
        return (run.exitCode, run.output)
    }
    #endif
}
