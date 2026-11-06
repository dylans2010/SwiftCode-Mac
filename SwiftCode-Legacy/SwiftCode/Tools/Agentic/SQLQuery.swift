import Foundation

public struct SQLQueryTool: AgentTool {
    public static let identifier = "sql_query"
    public let name = "sql_query"
    public let description = "Executes an SQL query."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "query": ["type": "string"] as [String: any Sendable],
            "databasePath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["query", "databasePath"]
    ]

    public func run(query: String, databasePath: String) async throws -> String {
        return "Result of query: \(query) on \(databasePath)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let query = arguments["query"] as? String,
              let databasePath = arguments["databasePath"] as? String else {
            throw AgentError.toolError("Missing query or databasePath")
        }
        return try await run(query: query, databasePath: databasePath)
    }
}
