import Foundation

public struct GenerateIntegrationTestsTool: AgentTool {
    public static let identifier = "generate_integration_tests"
    public let name = "generate_integration_tests"
    public let description = "Generates integration tests for the provided code."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "code": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["code"]
    ]

    public func run(code: String) async throws -> String {
        return "import XCTest\nclass GeneratedIntegrationTests: XCTestCase {}"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let code = arguments["code"] as? String else {
            throw AgentError.toolError("Missing code")
        }
        return try await run(code: code)
    }
}
