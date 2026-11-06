import Foundation

public struct ReadPullRequestTool: AgentTool {
    public static let identifier = "read_pull_request"
    public let name = "read_pull_request"
    public let description = "Reads content of a pull request."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "prNumber": ["type": "integer"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["prNumber"]
    ]

    public func run(prNumber: Int) async throws -> String {
        return "Content of PR #\(prNumber)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let prNumber = arguments["prNumber"] as? Int else {
            throw AgentError.toolError("Missing prNumber")
        }
        return try await run(prNumber: prNumber)
    }
}
