import Foundation

public struct GitShowTool: AgentTool {
    public static let identifier = "git_show"
    public let name = "git_show"
    public let description = "Shows details of a Git commit."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable],
            "hash": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath", "hash"]
    ]

    public func run(repositoryPath: String, hash: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["show", hash],
            workingDirectory: url
        )
        return result.stdout
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String,
              let hash = arguments["hash"] as? String else {
            throw AgentError.toolError("Missing repositoryPath or hash")
        }
        return try await run(repositoryPath: repositoryPath, hash: hash)
    }
}
