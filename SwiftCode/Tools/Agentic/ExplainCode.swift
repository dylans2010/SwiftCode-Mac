import Foundation

public struct ExplainCodeTool {
    public static let identifier = "explain_code"

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
}
