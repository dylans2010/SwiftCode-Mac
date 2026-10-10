import Foundation

public struct AssistManageMemoryTool: AssistTool {
    public let id = "manage_memory"
    public let name = "Manage Memory"
    public let description = "Manages saved memory entries in UserMemory.md. Modifies existing entries, deletes obsolete memory, or saves new details."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Manages saved memory entries. Accepts modifySaved to modify an entry, deleteContext to delete a memory piece, or saveToMemory to save new details.",
            properties: [
                "modifySaved": JSONSchema(type: "string", description: "Modifies an already saved entry. Can be 'Old content -> New content' or target text to update."),
                "deleteContext": JSONSchema(type: "string", description: "Deletes a piece of memory matching this context or text."),
                "saveToMemory": JSONSchema(type: "string", description: "Saves new details to the memory system.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard await AssistMemoryStore.shared.isMemoryEnabled else {
            return .failure("User has Memory module OFF.")
        }

        let modifySaved = (input["modifySaved"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let deleteContext = (input["deleteContext"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveToMemory = (input["saveToMemory"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (modifySaved != nil && !modifySaved!.isEmpty) ||
              (deleteContext != nil && !deleteContext!.isEmpty) ||
              (saveToMemory != nil && !saveToMemory!.isEmpty) else {
            return .failure("manage_memory requires at least one of modifySaved, deleteContext, or saveToMemory.")
        }

        var actionsTaken: [String] = []

        if let save = saveToMemory, !save.isEmpty {
            let success = await AssistMemoryStore.shared.saveToMemory(save)
            if success {
                actionsTaken.append("Saved new details to memory: \(save)")
            } else {
                actionsTaken.append("Failed to save to memory: \(save)")
            }
        }

        if let modify = modifySaved, !modify.isEmpty {
            let success = await AssistMemoryStore.shared.modifySaved(modify)
            if success {
                actionsTaken.append("Modified saved memory entry: \(modify)")
            } else {
                actionsTaken.append("Could not locate entry to modify: \(modify)")
            }
        }

        if let delete = deleteContext, !delete.isEmpty {
            let success = await AssistMemoryStore.shared.deleteContext(delete)
            if success {
                actionsTaken.append("Deleted memory context: \(delete)")
            } else {
                actionsTaken.append("Could not find matching memory context to delete: \(delete)")
            }
        }

        let summary = actionsTaken.joined(separator: "\n")
        return .success(summary, data: [
            "actions": summary
        ])
    }
}
