import Foundation

public struct AssistGitStashTool: AssistTool {
    public let id = "git_stash_operator"
    public let name = "Git Stash Operator"
    public let description = "Manages Git stashes (save, pop, list, show, drop) to safely stash and restore changes during refactoring."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Save, restore, or inspect git stashed changes in the active workspace.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'save', 'pop', 'list', 'show', 'drop'."),
                "message": JSONSchema(type: "string", description: "Optional descriptive message for 'save'."),
                "stashIndex": JSONSchema(type: "string", description: "Stash identifier for pop/show/drop (e.g. 'stash@{0}', defaults to 'stash@{0}').")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action")
        }

        let message = input["message"] as? String
        let stashIndex = (input["stashIndex"] as? String) ?? "stash@{0}"

        var arguments = ["stash"]

        switch action.lowercased() {
        case "save", "push":
            arguments.append("push")
            if let msg = message, !msg.isEmpty {
                arguments.append("-m")
                arguments.append(msg)
            }
        case "pop":
            arguments.append("pop")
            arguments.append(stashIndex)
        case "list":
            arguments.append("list")
        case "show":
            arguments.append("show")
            arguments.append("-p")
            arguments.append(stashIndex)
        case "drop":
            arguments.append("drop")
            arguments.append(stashIndex)
        default:
            return .failure("Unsupported action '\(action)'. Valid: save, pop, list, show, drop")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = context.workspaceRoot
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                let res = stdout.isEmpty ? (stderr.isEmpty ? "Git stash \(action) completed." : stderr) : stdout
                return .success(res)
            } else {
                return .failure("Git stash \(action) failed (exit \(process.terminationStatus)):\n\(stderr)\n\(stdout)")
            }
        } catch {
            return .failure("Failed to execute git stash: \(error.localizedDescription)")
        }
    }
}
