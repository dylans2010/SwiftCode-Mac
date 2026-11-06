//
//  AssistGitBranchManagerTool.swift
//  SwiftCode
//

import Foundation

public struct AssistGitBranchManagerTool: AssistTool {
    public let id = "git_branch_manager"
    public let name = "Git Branch Manager"
    public let description = "Inspects, lists, creates, switches, and manages Git branches in the workspace."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Manages repository branches. Actions: 'list', 'current', 'create', 'switch', 'delete'.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'list', 'current', 'create', 'switch', or 'delete'."),
                "branchName": JSONSchema(type: "string", description: "Branch name when creating, switching, or deleting.")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action")
        }
        let branchName = input["branchName"] as? String ?? ""

        var gitArgs: [String] = []
        switch action.lowercased() {
        case "list", "branches":
            gitArgs = ["branch", "-a"]
        case "current":
            gitArgs = ["branch", "--show-current"]
        case "create":
            guard !branchName.isEmpty else { return .failure("Action 'create' requires 'branchName'.") }
            gitArgs = ["checkout", "-b", branchName]
        case "switch", "checkout":
            guard !branchName.isEmpty else { return .failure("Action 'switch' requires 'branchName'.") }
            gitArgs = ["checkout", branchName]
        case "delete":
            guard !branchName.isEmpty else { return .failure("Action 'delete' requires 'branchName'.") }
            gitArgs = ["branch", "-d", branchName]
        default:
            return .failure("Unsupported action '\(action)'. Supported: list, current, create, switch, delete.")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = gitArgs
        proc.currentDirectoryURL = context.workspaceRoot

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if proc.terminationStatus == 0 {
                return .success(out.isEmpty ? "Branch operation '\(action)' succeeded." : out)
            } else {
                return .failure("Git branch operation failed: \(out)")
            }
        } catch {
            return .failure("Failed to execute git: \(error.localizedDescription)")
        }
    }
}
