import Foundation

public struct APIReferenceSearchTool {
    public static let identifier = "api_reference_search"

    public func run(query: String) async throws -> String {
        return "API Reference for: \(query)"
    }
}
