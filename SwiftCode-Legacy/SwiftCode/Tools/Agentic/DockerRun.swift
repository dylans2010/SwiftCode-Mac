import Foundation

public struct DockerRunTool: AgentTool {
    public static let identifier = "docker_run"
    public let name = "docker_run"
    public let description = "Runs a Docker container."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "image": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["image"]
    ]

    public func run(image: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/docker"),
            arguments: ["run", image]
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let image = arguments["image"] as? String else {
            throw AgentError.toolError("Missing image")
        }
        return try await run(image: image)
    }
}
