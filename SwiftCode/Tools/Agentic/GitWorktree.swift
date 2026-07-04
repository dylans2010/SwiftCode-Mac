import Foundation

public struct GitWorktreeTool: AgentTool {
    public static let identifier = "git_worktree"
    public let name = "git_worktree"
    public let description = "Manages Git worktrees."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable],
            "action": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath", "action"]
    ]

    public func run(repositoryPath: String, action: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["worktree", action],
            workingDirectory: url
        )
        return result.stdout
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String,
              let action = arguments["action"] as? String else {
            throw AgentError.toolError("Missing repositoryPath or action")
        }
        return try await run(repositoryPath: repositoryPath, action: action)
    }
}
