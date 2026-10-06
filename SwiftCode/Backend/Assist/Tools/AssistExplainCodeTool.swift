import Foundation

public struct AssistExplainCodeTool: AssistTool {
    public let id = "intel_explain_code"
    public let name = "Explain Code"
    public let description = "Provides a detailed explanation of the code at a path."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Provides a detailed explanation of the code at a path, using an LLM with a static fallback.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the file to explain.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        do {
            let content = try context.fileSystem.readFile(at: path)

            // LLM-powered explanation
            let provider = AssistModelProvider.openAI // Default for now
            let apiKey = await APIKeyManager.shared.retrieveKey(service: provider.apiKeyProvider)

            let prompt = """
            You are a Swift expert. Explain the following code file in detail.
            Keep it professional and concise.

            File: \(path)
            ---
            \(content)
            """

            let response = await AssistLLMService.generateResponse(prompt: prompt, provider: provider, apiKey: apiKey)

            if response.success {
                return .success("Explanation for \(path)", data: ["explanation": response.content])
            } else {
                // Fallback to static analysis if LLM fails
                let lines = content.components(separatedBy: .newlines)
                let summary = "File: \(path), Lines: \(lines.count). (LLM explanation failed: \(response.error ?? "unknown"))"
                return .success("Static analysis for \(path)", data: ["explanation": summary])
            }
        } catch {
            return .failure("Failed to explain \(path): \(error.localizedDescription)")
        }
    }
}
