import Foundation

public struct GitCommitTool: AgentTool {
    public static let identifier = "git_commit"
    public let name = "git_commit"
    public let description = "Commits staged changes to the git repository."
    public let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"],
            "message": ["type": "string"]
        ],
        "required": ["repositoryPath", "message"]
    ]

    public func run(repositoryPath: String, message: String) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["commit", "-m", message],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AgentError.toolError(result.stderr) }
    }

    public func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["repositoryPath"] as? String,
              let message = arguments["message"] as? String else {
            throw AgentError.toolError("Missing repositoryPath or message")
        }
        try await run(repositoryPath: path, message: message)
        return "Changes committed successfully"
    }
}
