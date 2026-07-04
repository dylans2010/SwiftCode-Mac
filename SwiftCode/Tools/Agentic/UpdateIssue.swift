import Foundation

public struct UpdateIssueTool {
    public static let identifier = "update_issue"

    public func run(issueNumber: Int, title: String?, body: String?) async throws -> String {
        return "Issue #\(issueNumber) updated"
    }
}
