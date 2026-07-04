import Foundation

public struct GlobSearchTool: AgentTool {
    public static let identifier = "glob_search"
    public let name = "glob_search"
    public let description = "Searches for files matching a glob pattern."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "pattern": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["pattern"]
    ]

    public func run(pattern: String) async throws -> [String] {
        // Simple implementation using find command
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/find"),
            arguments: [".", "-name", pattern]
        )
        return result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let pattern = arguments["pattern"] as? String else {
            throw AgentError.toolError("Missing pattern")
        }
        let results = try await run(pattern: pattern)
        if results.isEmpty {
            return "No matches found."
        }
        return results.joined(separator: "\n")
    }
}
