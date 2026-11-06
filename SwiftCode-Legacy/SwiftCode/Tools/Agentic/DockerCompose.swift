import Foundation

public struct DockerComposeTool: AgentTool {
    public static let identifier = "docker_compose"
    public let name = "docker_compose"
    public let description = "Runs docker-compose commands."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"] as [String: any Sendable],
            "action": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["path", "action"]
    ]

    public func run(path: String, action: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/docker-compose"),
            arguments: ["-f", path, action]
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String,
              let action = arguments["action"] as? String else {
            throw AgentError.toolError("Missing path or action")
        }
        return try await run(path: path, action: action)
    }
}
