import Foundation

public struct DocumentationSearchTool {
    public static let identifier = "documentation_search"

    public func run(query: String) async throws -> String {
        return "Documentation for: \(query)"
    }
}
