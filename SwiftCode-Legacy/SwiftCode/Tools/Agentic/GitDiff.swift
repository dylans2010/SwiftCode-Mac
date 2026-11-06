import Foundation

public struct GitDiffTool: AgentTool {
    public static let identifier = "git_diff"
    public let name = "git_diff"
    public let description = "Returns the diff of changes in the repository."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"],
            "file": ["type": "string"]
        ],
        "required": ["repositoryPath"]
    ]

    public func run(repositoryPath: String, file: String? = nil) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        var args = ["diff"]
        if let file = file { args.append(file) }
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: args,
            workingDirectory: url
        )
        return result.stdout
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["repositoryPath"] as? String else { throw AgentError.toolError("Missing repositoryPath") }
        let file = arguments["file"] as? String
        return try await run(repositoryPath: path, file: file)
    }
}
