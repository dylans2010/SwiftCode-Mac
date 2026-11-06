import Foundation

public struct GitCloneTool: AgentTool {
    public static let identifier = "git_clone"
    public let name = "git_clone"
    public let description = "Clones a Git repository."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "remoteURL": ["type": "string"] as [String: any Sendable],
            "destinationPath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["remoteURL", "destinationPath"]
    ]

    public func run(remoteURL: String, destinationPath: String) async throws {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["clone", remoteURL, destinationPath]
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let remoteURL = arguments["remoteURL"] as? String,
              let destinationPath = arguments["destinationPath"] as? String else {
            throw AgentError.toolError("Missing remoteURL or destinationPath")
        }
        try await run(remoteURL: remoteURL, destinationPath: destinationPath)
        return "Successfully cloned \(remoteURL) to \(destinationPath)"
    }
}
