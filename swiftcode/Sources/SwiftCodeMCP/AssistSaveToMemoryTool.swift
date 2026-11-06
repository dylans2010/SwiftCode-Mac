// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/AssistSaveToMemoryTool.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/AssistSaveToMemoryTool.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - App-global persistence to ~/Library/Application Support/SwiftCode/UserMemory.md shared across workspaces
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - ToolCapability — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - ToolRiskLevel — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - UserMemoryManager — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/UserMemoryManager.swift`)
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Memory.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

//
//  AssistSaveToMemoryTool.swift
//  SwiftCode
//

import Foundation
import SwiftCodeAssistant

public struct AssistSaveToMemoryTool: AssistTool {
    public let id = "save_to_memory"
    public let name = "Save to Memory"
    public let description = "Saves high-value architectural decisions, preferences, guidelines, and context to UserMemory.md."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Saves a fact, preference, or technical instruction to durable memory in UserMemory.md.",
            properties: [
                "key": JSONSchema(type: "string", description: "Short, descriptive unique key (e.g. ArchitectureStyle, DesignTokens, ConcurrencyRule)."),
                "value": JSONSchema(type: "string", description: "The content, guideline, or instruction to remember permanently."),
                "category": JSONSchema(type: "string", description: "Category name (e.g. Preferences, Architecture, Decisions, Rules, Project Context). Defaults to General.")
            ],
            required: ["key", "value"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let key = input["key"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: key")
        }
        guard let value = input["value"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: value")
        }
        let category = (input["category"] as? String) ?? "General"

        let success = await MainActor.run {
            UserMemoryManager.shared.saveMemory(key: key, value: value, category: category)
        }

        if success {
            return .success("Saved to memory [\(category)]: **\(key)** = \(value)\nPersisted to ~/Library/Application Support/SwiftCode/UserMemory.md")
        } else {
            return .failure("Memory recording is currently disabled in Assist Settings, or storage failed.")
        }
    }
}
