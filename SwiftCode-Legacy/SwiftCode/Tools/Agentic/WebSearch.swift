import Foundation

public struct WebSearchTool: AgentTool {
    public static let identifier = "web_search"
    public let name = "web_search"
    public let description = "Performs a web search."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "query": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["query"]
    ]

    public func run(query: String) async throws -> String {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://ddg-api.herokuapp.com/search?q=\(encodedQuery)") else {
            throw AppError.commonError("Invalid query")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? "No results"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let query = arguments["query"] as? String else {
            throw AgentError.toolError("Missing query")
        }
        return try await run(query: query)
    }
}
