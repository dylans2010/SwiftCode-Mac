import Foundation

public struct CreateIssueTool {
    public static let identifier = "create_issue"

    public func run(title: String, body: String) async throws -> String {
        return "Issue created: \(title)"
    }
}
