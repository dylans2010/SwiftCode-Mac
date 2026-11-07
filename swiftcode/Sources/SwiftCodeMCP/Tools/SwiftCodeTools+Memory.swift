import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
    var memoryTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let nonIdempotentMutation = MCPToolAnnotations(readOnly: false, idempotent: false)
        let destructive = MCPToolAnnotations(readOnly: false, destructive: true)
        return [
            tool("mem_store", "Store Memory",
                 "Stores information in the long-term memory graph.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "key": Schema.string("Memory key to store under."),
                                       "value": Schema.string("Value to store.")],
                                      required: ["key", "value"]),
                 output: Schema.output(["key": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.storeMemory(call)
            },
            tool("mem_retrieve", "Retrieve Memory",
                 "Retrieves information from the long-term memory graph.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "key": Schema.string("Memory key to look up.")],
                                      required: ["key"]),
                 output: Schema.output(["key": Schema.str, "value": Schema.str])) { h, call in
                try h.retrieveMemory(call)
            },
            tool("mem_clear", "Clear Memory",
                 "Clears all stored information in the memory graph.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["cleared": Schema.bool, "entriesCleared": Schema.int]),
                 annotations: destructive, writes: true) { h, call in
                try await h.clearMemory(call)
            },
            tool("mem_context_snapshot", "Context Snapshot",
                 "Captures a snapshot of the current environment and open files for future reference.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["snapshot_key": Schema.str, "latest_snapshot": Schema.str]),
                 annotations: nonIdempotentMutation, writes: true) { h, call in
                try await h.captureContextSnapshot(call)
            },
            tool("context_persistence_store", "Persistent Context Store",
                 "Stores and retrieves persistent key-value context across Assist sessions.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "key": Schema.string("Context key."),
                                       "action": Schema.string("One of 'set', 'get', or 'delete'. Default: \"get\"."),
                                       "value": Schema.string("Value to store. Required when action is 'set'.")],
                                      required: ["key"]),
                 output: Schema.output(["key": Schema.str, "action": Schema.str, "value": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.persistentContextStore(call)
            },
            tool("save_to_memory", "Save to Memory",
                 "Saves high-value architectural decisions, preferences, guidelines, and context to UserMemory.md.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "key": Schema.string("Short, descriptive unique key (e.g. ArchitectureStyle, DesignTokens, ConcurrencyRule)."),
                                       "value": Schema.string("The content, guideline, or instruction to remember permanently."),
                                       "category": Schema.string("Category name (e.g. Preferences, Architecture, Decisions, Rules, Project Context). Defaults to General.")],
                                      required: ["key", "value"]),
                 output: Schema.output(["key": Schema.str, "value": Schema.str, "category": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.saveToMemory(call)
            },
            tool("view_memory", "View Memory",
                 "Reads and retrieves stored context, preferences, and architectural decisions from UserMemory.md.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Optional search query to filter memory entries by key or content."),
                                       "category": Schema.string("Optional category filter (e.g. Preferences, Architecture, Rules).")]),
                 output: Schema.output(["entries": Schema.anyArray, "count": Schema.int, "report": Schema.str])) { h, call in
                try h.viewUserMemory(call)
            },
            tool("manage_memory", "Manage Memory",
                 "Allows Assist to edit, delete, or reorganize memories in UserMemory.md.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action to perform: 'add', 'edit', 'delete', or 'clear'."),
                                       "key": Schema.string("The memory key to add, edit, or delete."),
                                       "value": Schema.string("The new value when adding or editing a memory."),
                                       "category": Schema.string("Category name when adding or editing.")],
                                      required: ["action"]),
                 output: Schema.output(["action": Schema.str, "key": Schema.str, "category": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.manageMemory(call)
            },
            tool("conversation_context_manager", "Conversation Context Manager",
                 "Reads, updates, or checks the active conversation's dedicated context file (<conversation_id>.context.md).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action to perform: 'read' or 'update_summary'."),
                                       "notes": Schema.string("Updated notes or context to append when action is 'update_summary'.")],
                                      required: ["action"]),
                 output: Schema.output(["action": Schema.str, "context": Schema.str, "path": Schema.str]),
                 annotations: nonIdempotentMutation, writes: true) { h, call in
                try await h.conversationContext(call)
            },
        ]
    }

    func storeMemory(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let key = try call.require("key")
        guard !key.isEmpty else { throw MCPToolError("Missing required parameter: key") }
        let value = try call.require("value")
        guard !value.isEmpty else { throw MCPToolError("Missing required parameter: value") }
        SwiftCodeMemoryGraphStore.shared.store(workspace: memoryWorkspaceKey(in: s), key: key, value: value)
        return .structured(["key": .string(key)], summary: "Stored in memory: \(key)")
    }

    func retrieveMemory(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let key = try call.require("key")
        guard !key.isEmpty else { throw MCPToolError("Missing required parameter: key") }
        guard let value = SwiftCodeMemoryGraphStore.shared.retrieve(workspace: memoryWorkspaceKey(in: s), key: key) else {
            throw MCPToolError("Key not found in memory: \(key)")
        }
        return .structured(["key": .string(key), "value": .string(value)], summary: "Retrieved from memory: \(key)")
    }

    func clearMemory(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let cleared = SwiftCodeMemoryGraphStore.shared.clear(workspace: memoryWorkspaceKey(in: s))
        return .structured(["cleared": .bool(true), "entriesCleared": .int(cleared)], summary: "Memory cleared.")
    }

    func captureContextSnapshot(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let workspace = memoryWorkspaceKey(in: s)
        let sessionID = SwiftCodeMemoryGraphStore.shared.sessionID(workspace: workspace)
        let marker = UUID().uuidString
        let latestSnapshot = (try? AssistSnapshotFunctions.listSnapshots())?.first?.id ?? "none"
        let payload = "session=\(sessionID.uuidString)\nworkspace=\(workspace)\nlatest_snapshot=\(latestSnapshot)"
        SwiftCodeMemoryGraphStore.shared.store(workspace: workspace, key: "context_snapshot:\(marker)", value: payload)
        return .structured(["snapshot_key": .string("context_snapshot:\(marker)"), "latest_snapshot": .string(latestSnapshot)],
                           summary: "Context snapshot captured")
    }

    func persistentContextStore(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let action = (call.string("action") ?? "get").lowercased()
        let key = try call.require("key")
        guard !key.isEmpty else { throw MCPToolError("Missing key") }
        let url = contextStoreURL(in: s)
        var db = loadContextStore(in: s)
        switch action {
        case "set":
            guard let value = call.string("value") else { throw MCPToolError("Missing value") }
            db[key] = value
            let proposed = SwiftCodeContextStoreFormat.render(db)
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: ".assist_context_store.json",
                                       original: text(of: url), proposed: proposed,
                                       summary: "Store context for key \(key)"), call: call, session: s)
            return .structured(["key": .string(key), "action": .string("set"), "value": .string(value)],
                               summary: "Stored context for key \(key)")
        case "delete":
            db.removeValue(forKey: key)
            let proposed = SwiftCodeContextStoreFormat.render(db)
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: ".assist_context_store.json",
                                       original: text(of: url), proposed: proposed,
                                       summary: "Delete context key \(key)"), call: call, session: s)
            return .structured(["key": .string(key), "action": .string("delete"), "value": .string("")],
                               summary: "Deleted key \(key)")
        default:
            return .structured(["key": .string(key), "action": .string("get"), "value": .string(db[key] ?? "")],
                               summary: "Retrieved context for key \(key)")
        }
    }

    func saveToMemory(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let key = try call.require("key").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MCPToolError("Missing required parameter: key") }
        let value = try call.require("value").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw MCPToolError("Missing required parameter: value") }
        let rawCategory = (call.string("category") ?? "General").trimmingCharacters(in: .whitespacesAndNewlines)
        let category = rawCategory.isEmpty ? "General" : rawCategory
        let url = userMemoryURL(in: s)
        var entries = loadUserMemoryEntries(in: s)
        upsertUserMemoryEntry(&entries, key: key, value: value, category: category)
        let proposed = SwiftCodeUserMemoryFormat.render(entries)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: ".assist_temp/memory/UserMemory.md",
                                   original: text(of: url), proposed: proposed,
                                   summary: "Save memory '\(key)'"), call: call, session: s)
        return .structured(["key": .string(key), "value": .string(value), "category": .string(category)],
                           summary: "Saved to memory [\(category)]: **\(key)** = \(value)\nPersisted to .assist_temp/memory/UserMemory.md")
    }

    func viewUserMemory(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let query = call.string("query")
        let category = call.string("category")
        var entries = loadUserMemoryEntries(in: s)
        if let cat = category, !cat.isEmpty {
            entries = entries.filter { $0.category.caseInsensitiveCompare(cat) == .orderedSame }
        }
        if let q = query, !q.isEmpty {
            entries = entries.filter {
                $0.key.localizedCaseInsensitiveContains(q) || $0.value.localizedCaseInsensitiveContains(q)
            }
        }
        let iso = ISO8601DateFormatter()
        let jsonEntries: [AnyJSON] = entries.map { e in
            ["key": .string(e.key), "value": .string(e.value), "category": .string(e.category),
             "updatedAt": .string(iso.string(from: e.updatedAt))]
        }
        if entries.isEmpty {
            let fullDoc = text(of: userMemoryURL(in: s)) ?? ""
            if fullDoc.isEmpty {
                let report = "No memories are currently stored in UserMemory.md."
                return .structured(["entries": .array([]), "count": .int(0), "report": .string(report)], summary: report)
            }
            let report = "No memory items matched the filter. Full UserMemory.md:\n\n\(fullDoc)"
            return .structured(["entries": .array([]), "count": .int(0), "report": .string(report)], summary: report)
        }
        var report = "### Active User Memories (\(entries.count) items):\n\n"
        for item in entries {
            report += "- [\(item.category)] **\(item.key)**: \(item.value)\n"
        }
        return .structured(["entries": .array(jsonEntries), "count": .int(entries.count), "report": .string(report)],
                           summary: report)
    }

    func manageMemory(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.string("action") else {
            throw MCPToolError("Missing required parameter: action ('add', 'edit', 'delete', 'clear')")
        }
        let key = (call.string("key") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (call.string("value") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawCategory = (call.string("category") ?? "General").trimmingCharacters(in: .whitespacesAndNewlines)
        let category = rawCategory.isEmpty ? "General" : rawCategory
        let url = userMemoryURL(in: s)
        switch action.lowercased() {
        case "add", "edit", "save":
            guard !key.isEmpty, !value.isEmpty else {
                throw MCPToolError("Actions 'add' and 'edit' require both 'key' and 'value'.")
            }
            var entries = loadUserMemoryEntries(in: s)
            upsertUserMemoryEntry(&entries, key: key, value: value, category: category)
            try await commit(MCPChange(tool: call.name, path: url.path,
                                       relativePath: ".assist_temp/memory/UserMemory.md",
                                       original: text(of: url), proposed: SwiftCodeUserMemoryFormat.render(entries),
                                       summary: "Save memory '\(key)'"), call: call, session: s)
            return .structured(["action": .string(action.lowercased()), "key": .string(key), "category": .string(category)],
                               summary: "Memory '\(key)' successfully updated in UserMemory.md.")
        case "delete", "remove":
            guard !key.isEmpty else {
                throw MCPToolError("Action 'delete' requires 'key'.")
            }
            var entries = loadUserMemoryEntries(in: s)
            guard let idx = entries.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) else {
                throw MCPToolError("Memory entry '\(key)' was not found in UserMemory.md.")
            }
            entries.remove(at: idx)
            try await commit(MCPChange(tool: call.name, path: url.path,
                                       relativePath: ".assist_temp/memory/UserMemory.md",
                                       original: text(of: url), proposed: SwiftCodeUserMemoryFormat.render(entries),
                                       summary: "Delete memory '\(key)'"), call: call, session: s)
            return .structured(["action": .string(action.lowercased()), "key": .string(key), "category": .string("")],
                               summary: "Memory entry '\(key)' deleted from UserMemory.md.")
        case "clear":
            try await commit(MCPChange(tool: call.name, path: url.path,
                                       relativePath: ".assist_temp/memory/UserMemory.md",
                                       original: text(of: url), proposed: SwiftCodeUserMemoryFormat.header,
                                       summary: "Clear all memories"), call: call, session: s)
            return .structured(["action": .string("clear"), "key": .string(""), "category": .string("")],
                               summary: "All memories cleared from UserMemory.md.")
        default:
            throw MCPToolError("Unknown action '\(action)'. Supported actions: add, edit, delete, clear.")
        }
    }

    private func upsertUserMemoryEntry(_ entries: inout [SwiftCodeUserMemoryEntry], key: String, value: String, category: String) {
        if let idx = entries.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            entries[idx].value = value
            entries[idx].category = category
            entries[idx].updatedAt = Date()
        } else {
            entries.append(SwiftCodeUserMemoryEntry(key: key, value: value, category: category, updatedAt: Date()))
        }
    }

    func conversationContext(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.string("action") else {
            throw MCPToolError("Missing required parameter: action ('read' or 'update_summary')")
        }
        let url = conversationContextURL(in: s)
        switch action.lowercased() {
        case "read", "view":
            if let text = text(of: url) {
                return .structured(["action": .string("read"), "context": .string(text), "path": .string("")],
                                   summary: "Conversation Context:\n\n\(text)")
            }
            let report = "No custom context file found yet for the active conversation."
            return .structured(["action": .string("read"), "context": .string(""), "path": .string("")],
                               summary: report)
        case "update", "update_summary", "append":
            guard let notes = call.string("notes") else {
                throw MCPToolError("Action 'update_summary' requires non-empty 'notes'.")
            }
            var existing = text(of: url) ?? "# Conversation Context\n\n"
            existing += "\n### Additional Model Context (Updated \(ISO8601DateFormatter().string(from: Date()))):\n\(notes)\n"
            try await commit(MCPChange(tool: call.name, path: url.path,
                                       relativePath: ".assist_temp/memory/conversation_context.md",
                                       original: text(of: url), proposed: existing,
                                       summary: "Update conversation context"), call: call, session: s)
            return .structured(["action": .string("update_summary"), "context": .string(""), "path": .string(url.path)],
                               summary: "Successfully updated conversation context file at: \(url.path)")
        default:
            throw MCPToolError("Unsupported action '\(action)'. Use 'read' or 'update_summary'.")
        }
    }
}
