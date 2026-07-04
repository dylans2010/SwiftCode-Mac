import Foundation

public struct SearchIssuesTool {
    public static let identifier = "search_issues"

    public func run(query: String) async throws -> String {
        return "Search results for issues: \(query)"
    }
}
