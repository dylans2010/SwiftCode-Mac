import Foundation

public struct DockerBuildTool: AgentTool {
    public static let identifier = "docker_build"
    public let name = "docker_build"
    public let description = "Builds a Docker image."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"] as [String: any Sendable],
            "tag": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["path", "tag"]
    ]

    public func run(path: String, tag: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/docker"),
            arguments: ["build", "-t", tag, path]
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String,
              let tag = arguments["tag"] as? String else {
            throw AgentError.toolError("Missing path or tag")
        }
        return try await run(path: path, tag: tag)
    }
}
