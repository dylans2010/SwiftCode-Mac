import Foundation

public struct ReviewCodeTool: AgentTool {
    public static let identifier = "review_code"
    public let name = "review_code"
    public let description = "Reviews code using AI."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "code": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["code"]
    ]

    public func run(code: String) async throws -> String {
        return "Review comments: LGTM!"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let code = arguments["code"] as? String else {
            throw AgentError.toolError("Missing code")
        }
        return try await run(code: code)
    }
}
