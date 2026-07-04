import Foundation

public struct ReviewPullRequestTool: AgentTool {
    public static let identifier = "review_pull_request"
    public let name = "review_pull_request"
    public let description = "Reviews a pull request."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "prNumber": ["type": "integer"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["prNumber"]
    ]

    public func run(prNumber: Int) async throws -> String {
        return "Reviewing PR #\(prNumber)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let prNumber = arguments["prNumber"] as? Int else {
            throw AgentError.toolError("Missing prNumber")
        }
        return try await run(prNumber: prNumber)
    }
}
