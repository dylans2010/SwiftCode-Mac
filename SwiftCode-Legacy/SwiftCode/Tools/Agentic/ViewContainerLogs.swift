import Foundation

public struct ViewContainerLogsTool: AgentTool {
    public static let identifier = "view_container_logs"
    public let name = "view_container_logs"
    public let description = "Views logs for a Docker container."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "containerID": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["containerID"]
    ]

    public func run(containerID: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/docker"),
            arguments: ["logs", containerID]
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let containerID = arguments["containerID"] as? String else {
            throw AgentError.toolError("Missing containerID")
        }
        return try await run(containerID: containerID)
    }
}
