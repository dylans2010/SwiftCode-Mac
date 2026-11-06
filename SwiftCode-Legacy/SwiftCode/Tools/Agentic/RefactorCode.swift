import Foundation

public struct RefactorCodeTool: AgentTool {
    public static let identifier = "refactor_code"
    public let name = "refactor_code"
    public let description = "Refactors code based on instructions."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "code": ["type": "string"] as [String: any Sendable],
            "instructions": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["code", "instructions"]
    ]

    public func run(code: String, instructions: String) async throws -> String {
        return "// Refactored code\n\(code)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let code = arguments["code"] as? String,
              let instructions = arguments["instructions"] as? String else {
            throw AgentError.toolError("Missing code or instructions")
        }
        return try await run(code: code, instructions: instructions)
    }
}
