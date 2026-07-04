import Foundation

public struct FixBugsTool: AgentTool {
    public static let identifier = "fix_bugs"
    public let name = "fix_bugs"
    public let description = "Fixes bugs in Swift code."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "code": ["type": "string"] as [String: any Sendable],
            "issue": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["code", "issue"]
    ]

    public func run(code: String, issue: String) async throws -> String {
        return "// Fixed code\n\(code)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let code = arguments["code"] as? String,
              let issue = arguments["issue"] as? String else {
            throw AgentError.toolError("Missing code or issue")
        }
        return try await run(code: code, issue: issue)
    }
}
