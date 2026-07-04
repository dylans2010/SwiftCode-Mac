import Foundation

public struct GitAddTool: AgentTool {
    public static let identifier = "git_add"
    public let name = "git_add"
    public let description = "Adds files to the git staging area."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"],
            "files": ["type": "array", "items": ["type": "string"]]
        ],
        "required": ["repositoryPath", "files"]
    ]

    public func run(repositoryPath: String, files: [String]) async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["add"] + files,
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AgentError.toolError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["repositoryPath"] as? String,
              let files = arguments["files"] as? [String] else {
            throw AgentError.toolError("Missing repositoryPath or files")
        }
        try await run(repositoryPath: path, files: files)
        return "Files added successfully"
    }
}
