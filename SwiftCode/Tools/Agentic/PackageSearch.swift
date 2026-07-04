import Foundation

public struct PackageSearchTool: AgentTool {
    public static let identifier = "package_search"
    public let name = "package_search"
    public let description = "Searches for packages."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "query": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["query"]
    ]

    public func run(query: String) async throws -> String {
        return "Package search results for: \(query)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let query = arguments["query"] as? String else {
            throw AgentError.toolError("Missing query")
        }
        return try await run(query: query)
    }
}
