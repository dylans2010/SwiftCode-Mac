import Foundation

public struct GoBuildTool: AgentTool {
    public static let identifier = "go_build"
    public let name = "go_build"
    public let description = "Builds a Go project."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["path"]
    ]

    public func run(path: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/go"),
            arguments: ["build"],
            workingDirectory: URL(fileURLWithPath: path)
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AgentError.toolError("Missing path")
        }
        return try await run(path: path)
    }
}
