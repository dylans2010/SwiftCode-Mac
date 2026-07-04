import Foundation

public struct CreateIssueTool: AgentTool {
    public static let identifier = "create_issue"
    public let name = "create_issue"
    public let description = "Creates an issue."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"] as [String: any Sendable],
            "body": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["title", "body"]
    ]

    public func run(title: String, body: String) async throws -> String {
        return "Issue created: \(title)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let title = arguments["title"] as? String,
              let body = arguments["body"] as? String else {
            throw AgentError.toolError("Missing title or body")
        }
        return try await run(title: title, body: body)
    }
}
