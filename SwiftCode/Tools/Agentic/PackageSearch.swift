import Foundation

public struct PackageSearchTool {
    public static let identifier = "package_search"

    public func run(query: String) async throws -> String {
        return "Package search results for: \(query)"
    }
}
