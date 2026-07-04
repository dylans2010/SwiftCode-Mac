import Foundation

public struct SQLQueryTool {
    public static let identifier = "sql_query"

    public func run(query: String, databasePath: String) async throws -> String {
        return "Result of query: \(query) on \(databasePath)"
    }
}
