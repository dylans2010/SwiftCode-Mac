import Foundation

public struct GitStashTool: AgentTool {
    public static let identifier = "git_stash"
    public let name = "git_stash"
    public let description = "Stashes changes in the working directory."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable],
            "action": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath"]
    ]

    public func run(repositoryPath: String, action: String = "push") async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["stash", action],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String else {
            throw AgentError.toolError("Missing repositoryPath")
        }
        let action = arguments["action"] as? String ?? "push"
        try await run(repositoryPath: repositoryPath, action: action)
        return "Successfully executed git stash \(action)"
    }
}
