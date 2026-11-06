import Foundation

public struct ExplainCodeTool: AgentTool {
    public static let identifier = "explain_code"
    public let name = "explain_code"
    public let description = "Explains code using AI."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "code": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["code"]
    ]

    public func run(code: String) async throws -> String {
        let response = try await OpenRouterClient.shared.streamChatCompletion(request: AIAssistantRequest(
            model: "openai/gpt-4o-mini",
            messages: [AIMessage(role: .user, content: "Explain this code:\n\(code)")]
        ))
        var fullExplanation = ""
        for try await chunk in response {
            fullExplanation += chunk
        }
        return fullExplanation
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let code = arguments["code"] as? String else {
            throw AgentError.toolError("Missing code")
        }
        return try await run(code: code)
    }
}
