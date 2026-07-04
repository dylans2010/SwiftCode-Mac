import Foundation

public struct CreatePullRequestTool {
    public static let identifier = "create_pull_request"

    public func run(title: String, body: String, head: String, base: String) async throws -> String {
        return "PR created: \(title)"
    }
}
