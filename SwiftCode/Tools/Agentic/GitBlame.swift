import Foundation

public struct GitBlameTool: AgentTool {
    public static let identifier = "git_blame"
    public let name = "git_blame"
    public let description = "Shows Git blame for a file."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable],
            "file": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath", "file"]
    ]

    public func run(repositoryPath: String, file: String) async throws -> String {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["blame", file],
            workingDirectory: url
        )
        return result.stdout
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String,
              let file = arguments["file"] as? String else {
            throw AgentError.toolError("Missing repositoryPath or file")
        }
        return try await run(repositoryPath: repositoryPath, file: file)
    }
}
