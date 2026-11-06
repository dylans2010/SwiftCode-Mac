import Foundation

public struct GitPullTool: AgentTool {
    public static let identifier = "git_pull"
    public let name = "git_pull"
    public let description = "Pulls changes from a remote repository."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath"]
    ]

    public func run(repositoryPath: String) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["pull"],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String else {
            throw AgentError.toolError("Missing repositoryPath")
        }
        try await run(repositoryPath: repositoryPath)
        return "Successfully pulled changes"
    }
}
