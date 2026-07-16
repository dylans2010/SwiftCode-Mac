import Foundation

public struct AssistRefactorTool: AssistTool {
    public let id = "code_refactor"
    public let name = "Refactor"
    public let description = "Performs code refactoring (e.g., extract method, rename variable) intelligently."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        guard let actionDescription = input["action"] as? String else {
            return .failure("Missing required parameter: action")
        }

        do {
            let content = try context.fileSystem.readFile(at: path)

            let provider = AssistModelProvider.openAI // Default for now
            let apiKey = APIKeyManager.shared.retrieveKey(service: provider.apiKeyProvider)

            let prompt = """
            You are a refactoring engine. Apply the following refactoring action to the code.
            Return ONLY the modified code, no preamble.

            Action: \(actionDescription)
            File: \(path)
            ---
            \(content)
            """

            let response = await AssistLLMService.generateResponse(prompt: prompt, provider: provider, apiKey: apiKey)

            if response.success {
                let updatedCode = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "```swift", with: "")
                    .replacingOccurrences(of: "```", with: "")

                try context.fileSystem.writeFile(at: path, content: updatedCode)
                return .success("Refactoring '\(actionDescription)' applied to \(path)")
            } else {
                return .failure("Refactor LLM failed: \(response.error ?? "unknown")")
            }
        } catch {
            return .failure("Refactor failed at \(path): \(error.localizedDescription)")
        }
    }
}
