import Foundation

public struct APIReferenceSearchTool: AgentTool {
    public static let identifier = "api_reference_search"
    public let name = "api_reference_search"
    public let description = "Searches for API references."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "query": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["query"]
    ]

    public func run(query: String) async throws -> String {
        return "API Reference for: \(query)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let query = arguments["query"] as? String else {
            throw AgentError.toolError("Missing query")
        }
        return try await run(query: query)
    }
}
