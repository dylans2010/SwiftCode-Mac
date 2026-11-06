import Foundation

public struct GitRevertTool: AgentTool {
    public static let identifier = "git_revert"
    public let name = "git_revert"
    public let description = "Reverts a Git commit."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable],
            "hash": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath", "hash"]
    ]

    public func run(repositoryPath: String, hash: String) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["revert", "--no-edit", hash],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String,
              let hash = arguments["hash"] as? String else {
            throw AgentError.toolError("Missing repositoryPath or hash")
        }
        try await run(repositoryPath: repositoryPath, hash: hash)
        return "Successfully reverted \(hash)"
    }
}
