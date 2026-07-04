import Foundation

public struct DocumentationSearchTool: AgentTool {
    public static let identifier = "documentation_search"
    public let name = "documentation_search"
    public let description = "Searches for documentation."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "query": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["query"]
    ]

    public func run(query: String) async throws -> String {
        return "Documentation for: \(query)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let query = arguments["query"] as? String else {
            throw AgentError.toolError("Missing query")
        }
        return try await run(query: query)
    }
}
