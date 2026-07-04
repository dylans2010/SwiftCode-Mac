import Foundation

public struct SemanticCodeSearchTool: AgentTool {
    public static let identifier = "semantic_code_search"
    public let name = "semantic_code_search"
    public let description = "Performs semantic search on code."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "query": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["query"]
    ]

    public func run(query: String) async throws -> [String] {
        return ["Results for semantic search: \(query)"]
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let query = arguments["query"] as? String else {
            throw AgentError.toolError("Missing query")
        }
        let results = try await run(query: query)
        return results.joined(separator: "\n")
    }
}
