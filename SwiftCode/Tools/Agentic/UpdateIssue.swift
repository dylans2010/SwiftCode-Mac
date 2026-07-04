import Foundation

public struct UpdateIssueTool: AgentTool {
    public static let identifier = "update_issue"
    public let name = "update_issue"
    public let description = "Updates an issue."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "issueNumber": ["type": "integer"] as [String: any Sendable],
            "title": ["type": "string"] as [String: any Sendable],
            "body": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["issueNumber"]
    ]

    public func run(issueNumber: Int, title: String?, body: String?) async throws -> String {
        return "Issue #\(issueNumber) updated"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let issueNumber = arguments["issueNumber"] as? Int else {
            throw AgentError.toolError("Missing issueNumber")
        }
        let title = arguments["title"] as? String
        let body = arguments["body"] as? String
        return try await run(issueNumber: issueNumber, title: title, body: body)
    }
}
