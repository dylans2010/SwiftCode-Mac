import Foundation

public struct CreatePullRequestTool: AgentTool {
    public static let identifier = "create_pull_request"
    public let name = "create_pull_request"
    public let description = "Creates a pull request."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"] as [String: any Sendable],
            "body": ["type": "string"] as [String: any Sendable],
            "head": ["type": "string"] as [String: any Sendable],
            "base": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["title", "body", "head", "base"]
    ]

    public func run(title: String, body: String, head: String, base: String) async throws -> String {
        return "PR created: \(title)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let title = arguments["title"] as? String,
              let body = arguments["body"] as? String,
              let head = arguments["head"] as? String,
              let base = arguments["base"] as? String else {
            throw AgentError.toolError("Missing title, body, head, or base")
        }
        return try await run(title: title, body: body, head: head, base: base)
    }
}
