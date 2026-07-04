import Foundation

public struct ReviewPullRequestTool {
    public static let identifier = "review_pull_request"

    public func run(prNumber: Int) async throws -> String {
        return "Reviewing PR #\(prNumber)"
    }
}
