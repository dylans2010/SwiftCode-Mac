import Foundation

public struct GenerateUnitTestsTool: AgentTool {
    public static let identifier = "generate_unit_tests"
    public let name = "generate_unit_tests"
    public let description = "Generates unit tests for the provided code."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "code": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["code"]
    ]

    public func run(code: String) async throws -> String {
        return "import XCTest\nclass GeneratedTests: XCTestCase {}"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let code = arguments["code"] as? String else {
            throw AgentError.toolError("Missing code")
        }
        return try await run(code: code)
    }
}
