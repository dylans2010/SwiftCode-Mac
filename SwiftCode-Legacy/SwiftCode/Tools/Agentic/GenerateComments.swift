import Foundation

public struct GenerateCommentsTool: AgentTool {
    public static let identifier = "generate_comments"
    public let name = "generate_comments"
    public let description = "Generates comments for the provided code."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "code": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["code"]
    ]

    public func run(code: String) async throws -> String {
        return "// Comments for the provided code"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let code = arguments["code"] as? String else {
            throw AgentError.toolError("Missing code")
        }
        return try await run(code: code)
    }
}
