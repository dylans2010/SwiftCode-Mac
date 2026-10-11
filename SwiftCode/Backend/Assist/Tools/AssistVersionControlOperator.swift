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
                "action": JSONSchema(type: "string", description: "The git action to perform: status, commit, branch, rollback, or diff."),
                "message": JSONSchema(type: "string", description: "The commit message (used for commit action)."),
                "name": JSONSchema(type: "string", description: "The branch name (used for branch action).")
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

        default:
            let result = try runGit(args: ["status", "--short"], cwd: cwd)
            guard result.status == 0 else {
                return .failure("Git status failed: \(result.output)")
            }
            return .success("Git action executed: status", data: ["output": result.output])
        }
        #else
        return .failure("Version control operations require macOS runtime")
        #endif
    }

    #if os(macOS)
    private func isValidRefName(_ ref: String) -> Bool {
        guard !ref.isEmpty else { return false }
        let forbidden = [" ", ";", "&", "|", "`", "$", "(", ")", "<", ">", "\"", "'", "\\", "\n", "\r", "\t", "..", "~", "^", ":", "?", "*", "["]
        for char in forbidden {
            if ref.contains(char) && !(ref.contains("HEAD~") || ref.contains("HEAD^")) {
                return false
            }
        }
        return true
    }

    private func runGit(args: [String], cwd: String) throws -> (status: Int32, output: String) {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, output)
    }
    #endif
}
