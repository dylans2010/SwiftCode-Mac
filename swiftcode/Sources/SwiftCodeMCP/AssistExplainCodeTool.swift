// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/AssistExplainCodeTool.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/AssistExplainCodeTool.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - LLM-powered code explanation via AssistLLMService (OpenAI provider) — destination returns static analysis only
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AssistLLMService — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AssistModels.swift`)
//   - AssistModelProvider — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AssistModels.swift`)
//   - ToolCapability — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - ToolRiskLevel — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Planning.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

import Foundation
import SwiftCodeAssistant

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
            let apiKey = await provider.storedAPIKey()

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
