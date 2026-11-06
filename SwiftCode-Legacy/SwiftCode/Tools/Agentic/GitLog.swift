import Foundation

public struct GitLogTool: AgentTool {
    public static let identifier = "git_log"
    public let name = "git_log"
    public let description = "Shows Git log for a repository."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath"]
    ]

    public func run(repositoryPath: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["log", "--oneline", "-n", "20"],
            workingDirectory: url
        )
        return result.stdout
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String else {
            throw AgentError.toolError("Missing repositoryPath")
        }
        return try await run(repositoryPath: repositoryPath)
    }
}
