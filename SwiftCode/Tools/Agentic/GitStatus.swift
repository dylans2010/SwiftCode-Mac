import Foundation

public struct GitStatusTool: AgentTool {
    public static let identifier = "git_status"
    public let name = "git_status"
    public let description = "Returns the status of the git repository."
    public let schema: [String: Any] = [
        "type": "object",
        "properties": ["repositoryPath": ["type": "string"]],
        "required": ["repositoryPath"]
    ]

    public func run(repositoryPath: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["status", "--porcelain"],
            workingDirectory: url
        )
        return result.stdout
    }

    public func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["repositoryPath"] as? String else { throw AgentError.toolError("Missing repositoryPath") }
        return try await run(repositoryPath: path)
    }
}
