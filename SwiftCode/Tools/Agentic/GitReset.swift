import Foundation

public struct GitResetTool: AgentTool {
    public static let identifier = "git_reset"
    public let name = "git_reset"
    public let description = "Resets the current HEAD to a specified state."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repositoryPath": ["type": "string"] as [String: any Sendable],
            "mode": ["type": "string"] as [String: any Sendable],
            "target": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repositoryPath"]
    ]

    public func run(repositoryPath: String, mode: String = "--hard", target: String = "HEAD") async throws {
        let url = URL(fileURLWithPath: repositoryPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["reset", mode, target],
            workingDirectory: url
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repositoryPath = arguments["repositoryPath"] as? String else {
            throw AgentError.toolError("Missing repositoryPath")
        }
        let mode = arguments["mode"] as? String ?? "--hard"
        let target = arguments["target"] as? String ?? "HEAD"
        try await run(repositoryPath: repositoryPath, mode: mode, target: target)
        return "Successfully reset to \(target) with mode \(mode)"
    }
}
