import Foundation

public struct GenerateCodeTool: AgentTool {
    public static let identifier = "generate_code"
    public let name = "generate_code"
    public let description = "Generates code based on a prompt."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "prompt": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["prompt"]
    ]

    public func run(prompt: String) async throws -> String {
        return "// Generated code based on: \(prompt)\nfunc generated() {}"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let prompt = arguments["prompt"] as? String else {
            throw AgentError.toolError("Missing prompt")
        }
        return try await run(prompt: prompt)
    }
}
