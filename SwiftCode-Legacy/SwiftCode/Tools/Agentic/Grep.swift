import Foundation

public struct GrepTool: AgentTool {
    public static let identifier = "grep"
    public let name = "grep"
    public let description = "Searches for a pattern in a directory using grep."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "pattern": ["type": "string"] as [String: any Sendable],
            "directory": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["pattern", "directory"]
    ]

    public func run(pattern: String, directory: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/grep"),
            arguments: ["-r", "-n", pattern, directory]
        )
        return result.stdout
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let pattern = arguments["pattern"] as? String,
              let directory = arguments["directory"] as? String else {
            throw AgentError.toolError("Missing pattern or directory")
        }
        return try await run(pattern: pattern, directory: directory)
    }
}
