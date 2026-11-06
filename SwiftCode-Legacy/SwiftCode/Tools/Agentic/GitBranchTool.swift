import Foundation

public struct GitBranchTool: AgentTool {
    public static let identifier = "git_branch"
    public let name = "git_branch"
    public let description = "Lists Git branches."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath"]
    ]

    public func run(repositoryPath: String) async throws -> [String] {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["branch", "--format=%(refname:short)"],
            workingDirectory: url
        )
        return result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String else {
            throw AgentError.toolError("Missing repositoryPath")
        }
        let branches = try await run(repositoryPath: repositoryPath)
        return branches.joined(separator: "\n")
    }
}
