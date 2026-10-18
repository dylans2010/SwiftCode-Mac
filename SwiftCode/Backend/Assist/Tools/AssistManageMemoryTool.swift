//
//  AssistManageMemoryTool.swift
//  SwiftCode
//

import Foundation

public struct AssistManageMemoryTool: AssistTool {
    public let id = "manage_memory"
    public let name = "Manage Memory"
    public let description = "Allows Assist to edit, delete, or reorganize memories in UserMemory.md."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Directly manage entries in UserMemory.md. Supports actions: add, edit, delete, clear.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action to perform: 'add', 'edit', 'delete', or 'clear'."),
                "key": JSONSchema(type: "string", description: "The memory key to add, edit, or delete."),
                "value": JSONSchema(type: "string", description: "The new value when adding or editing a memory."),
                "category": JSONSchema(type: "string", description: "Category name when adding or editing.")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action ('add', 'edit', 'delete', 'clear')")
        }
        let key = input["key"] as? String ?? ""
        let value = input["value"] as? String ?? ""
        let category = input["category"] as? String ?? "General"

        switch action.lowercased() {
        case "add", "edit", "save":
            guard !key.isEmpty, !value.isEmpty else {
                return .failure("Actions 'add' and 'edit' require both 'key' and 'value'.")
            }
            let success = await MainActor.run {
                UserMemoryManager.shared.saveMemory(key: key, value: value, category: category)
            }
            if success {
                return .success("Memory '\(key)' successfully updated in UserMemory.md.")
            } else {
                return .failure("Failed to save memory. Memory recording may be disabled in settings.")
            }

        case "delete", "remove":
            guard !key.isEmpty else {
                return .failure("Action 'delete' requires 'key'.")
            }
            let success = await MainActor.run {
                UserMemoryManager.shared.deleteMemory(key: key)
            }
            if success {
                return .success("Memory entry '\(key)' deleted from UserMemory.md.")
            } else {
                return .failure("Memory entry '\(key)' was not found in UserMemory.md.")
            }

        case "clear":
            let success = await MainActor.run {
                UserMemoryManager.shared.clearAll()
            }
            if success {
                return .success("All memories cleared from UserMemory.md.")
            } else {
                return .failure("Failed to clear UserMemory.md.")
            }

        default:
            return .failure("Unknown action '\(action)'. Supported actions: add, edit, delete, clear.")
        }
    }
}
