//
//  AssistSaveToMemoryTool.swift
//  SwiftCode
//

import Foundation

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
