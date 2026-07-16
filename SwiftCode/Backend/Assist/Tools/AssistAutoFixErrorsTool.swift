import Foundation

public struct AssistAutoFixErrorsTool: AssistTool {
    public let id = "intel_autofix"
    public let name = "Auto-Fix Errors"
    public let description = "Attempts to automatically fix detected compilation or linting errors."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let path = input["path"] as? String ?? "."
        let targetURL = AssistToolingSupport.resolvePath(path, workspaceRoot: context.workspaceRoot)

        do {
            let lintOutput = try await AssistExecutionFunctions.executeTask(id: "lint_project", context: context)

            if !lintOutput.contains("issue(s)") {
                return .success("No lint issues to fix in \(path)")
            }

            // LLM-powered fix
            let original = try context.fileSystem.readFile(at: path)
            let provider = AssistModelProvider.openAI
            let apiKey = APIKeyManager.shared.retrieveKey(service: provider.apiKeyProvider)

            let prompt = """
            Fix the linting issues in this Swift file.
            Issues: \(lintOutput)

            Return ONLY the fixed code.

            File: \(path)
            ---
            \(original)
            """

            let response = await AssistLLMService.generateResponse(prompt: prompt, provider: provider, apiKey: apiKey)

            if response.success {
                let fixedCode = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "```swift", with: "")
                    .replacingOccurrences(of: "```", with: "")

                try context.fileSystem.writeFile(at: path, content: fixedCode)
                return .success("Auto-fix applied successfully to \(path)", data: ["fixedCount": "1"])
            } else {
                return .failure("LLM failed to fix errors: \(response.error ?? "unknown")")
            }
        } catch {
            return .failure("Auto-fix failed: \(error.localizedDescription)")
        }
    }
}
