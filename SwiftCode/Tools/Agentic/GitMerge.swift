import Foundation

public struct GitMergeTool: AgentTool {
    public static let identifier = "git_merge"
    public let name = "git_merge"
    public let description = "Merges a Git branch."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable],
            "branch": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath", "branch"]
    ]

    public func run(repositoryPath: String, branch: String) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["merge", branch],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String,
              let branch = arguments["branch"] as? String else {
            throw AgentError.toolError("Missing repositoryPath or branch")
        }
        try await run(repositoryPath: repositoryPath, branch: branch)
        return "Successfully merged branch \(branch)"
    }
}
