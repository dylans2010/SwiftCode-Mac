import Foundation

public struct AssistGitStashTool: AssistTool {
    public let id = "git_stash"
    public let name = "Git Stash"
    public let description = "Lists, creates, applies, pops, or drops git stashes in the workspace repository."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists, creates, applies, pops, or drops git stashes in the workspace repository.",
            properties: [
                "action": JSONSchema(type: "string", description: "Stash action: list, push, pop, apply, or drop. Default: list."),
                "message": JSONSchema(type: "string", description: "Message for the push action. Default: Assist stash."),
                "index": JSONSchema(type: "string", description: "Stash index as a decimal string for the drop action. Default: 0.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let action = ((input["action"] as? String) ?? "list").lowercased()
        let allowed = ["list", "push", "pop", "apply", "drop"]
        guard allowed.contains(action) else {
            return .failure("Invalid stash action '\(action)'. Allowed: list, push, pop, apply, drop.")
        }

        switch action {
        case "list":
            return runAndReport(args: ["stash", "list"], action: action, cwd: context.workspaceRoot)
        case "push":
            let message = (input["message"] as? String) ?? ""
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("\0") {
                return .failure("Stash message must not contain NUL characters.")
            }
            let finalMessage = trimmed.isEmpty ? "Assist stash" : trimmed
            return runAndReport(args: ["stash", "push", "-m", finalMessage], action: action, cwd: context.workspaceRoot)
        case "pop":
            return runAndReport(args: ["stash", "pop"], action: action, cwd: context.workspaceRoot)
        case "apply":
            return runAndReport(args: ["stash", "apply"], action: action, cwd: context.workspaceRoot)
        case "drop":
            var indexRaw = "0"
            if let s = input["index"] as? String {
                indexRaw = s
            } else if let i = input["index"] as? Int {
                indexRaw = String(i)
            }
            guard let index = Int(indexRaw.trimmingCharacters(in: .whitespaces)), index >= 0 else {
                return .failure("Invalid stash index '\(indexRaw)'. Expected a non-negative integer.")
            }
            return runAndReport(args: ["stash", "drop", "stash@{\(index)}"], action: action, cwd: context.workspaceRoot)
        default:
            return .failure("Invalid stash action '\(action)'.")
        }
    }

    private func runAndReport(args: [String], action: String, cwd: URL) -> AssistToolResult {
        let result = runGit(args: args, cwd: cwd)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0 else {
            return .failure("Git stash \(action) failed: \(output.isEmpty ? "unknown error" : output)")
        }
        let display = output.isEmpty ? "Git stash \(action) completed with no output." : output
        return .success("Git stash \(action) succeeded.\n\(display)", data: ["action": action, "output": output])
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
