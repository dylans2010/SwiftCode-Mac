import Foundation

public struct ReadPullRequestTool {
    public static let identifier = "read_pull_request"

    public func run(prNumber: Int) async throws -> String {
        return "Content of PR #\(prNumber)"
    }
}
