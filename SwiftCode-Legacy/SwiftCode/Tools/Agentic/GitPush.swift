import Foundation

public struct GitPushTool: AgentTool {
    public static let identifier = "git_push"
    public let name = "git_push"
    public let description = "Pushes committed changes to the remote repository."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": ["repositoryPath": ["type": "string"]],
        "required": ["repositoryPath"]
    ]

    public func run(repositoryPath: String) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["push"],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AgentError.toolError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["repositoryPath"] as? String else { throw AgentError.toolError("Missing repositoryPath") }
        try await run(repositoryPath: path)
        return "Push successful"
    }
}
