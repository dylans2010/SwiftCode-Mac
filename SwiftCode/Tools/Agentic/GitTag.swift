import Foundation

public struct GitTagTool: AgentTool {
    public static let identifier = "git_tag"
    public let name = "git_tag"
    public let description = "Lists Git tags."
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
            arguments: ["tag"],
            workingDirectory: url
        )
        return result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String else {
            throw AgentError.toolError("Missing repositoryPath")
        }
        let tags = try await run(repositoryPath: repositoryPath)
        return tags.joined(separator: "\n")
    }
}
