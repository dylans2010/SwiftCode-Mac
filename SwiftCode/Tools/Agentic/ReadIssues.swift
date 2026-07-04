import Foundation

public struct ReadIssuesTool: AgentTool {
    public static let identifier = "read_issues"
    public let name = "read_issues"
    public let description = "Reads issues for a repository."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "repository": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["repository"]
    ]

    public func run(repository: String) async throws -> String {
        return "List of issues for \(repository)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let repository = arguments["repository"] as? String else {
            throw AgentError.toolError("Missing repository")
        }
        return try await run(repository: repository)
    }
}
