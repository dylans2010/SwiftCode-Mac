import Foundation

public struct SearchIssuesTool: AgentTool {
    public static let identifier = "search_issues"
    public let name = "search_issues"
    public let description = "Searches for issues."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "query": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["query"]
    ]

    public func run(query: String) async throws -> String {
        return "Search results for issues: \(query)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let query = arguments["query"] as? String else {
            throw AgentError.toolError("Missing query")
        }
        return try await run(query: query)
    }
}
