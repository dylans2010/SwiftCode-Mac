//
//  AssistViewMemoryTool.swift
//  SwiftCode
//

import Foundation

public struct AssistViewMemoryTool: AssistTool {
    public let id = "view_memory"
    public let name = "View Memory"
    public let description = "Reads and retrieves stored context, preferences, and architectural decisions from UserMemory.md."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Retrieves durable memories stored in UserMemory.md. Can filter by query or category.",
            properties: [
                "query": JSONSchema(type: "string", description: "Optional search query to filter memory entries by key or content."),
                "category": JSONSchema(type: "string", description: "Optional category filter (e.g. Preferences, Architecture, Rules).")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let query = input["query"] as? String
        let category = input["category"] as? String

        let entries = await MainActor.run {
            var items = UserMemoryManager.shared.entries
            if let cat = category, !cat.isEmpty {
                items = items.filter { $0.category.caseInsensitiveCompare(cat) == .orderedSame }
            }
            if let q = query, !q.isEmpty {
                items = items.filter {
                    $0.key.localizedCaseInsensitiveContains(q) ||
                    $0.value.localizedCaseInsensitiveContains(q)
                }
            }
            return items
        }

        if entries.isEmpty {
            let fullDoc = await MainActor.run { UserMemoryManager.shared.readMemoryMarkdown() }
            if fullDoc.isEmpty {
                return .success("No memories are currently stored in UserMemory.md.")
            } else {
                return .success("No memory items matched the filter. Full UserMemory.md:\n\n\(fullDoc)")
            }
        }

        var report = "### Active User Memories (\(entries.count) items):\n\n"
        for item in entries {
            report += "- [\(item.category)] **\(item.key)**: \(item.value)\n"
        }
        return .success(report)
    }
}
