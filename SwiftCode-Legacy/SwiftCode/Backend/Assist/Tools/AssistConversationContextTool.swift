//
//  AssistConversationContextTool.swift
//  SwiftCode
//

import Foundation

public struct AssistConversationContextTool: AssistTool {
    public let id = "conversation_context_manager"
    public let name = "Conversation Context Manager"
    public let description = "Reads, updates, or checks the active conversation's dedicated context file (<conversation_id>.context.md)."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Manage or read the active conversation's context file to retain architectural focus and conversation continuity.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action to perform: 'read' or 'update_summary'."),
                "notes": JSONSchema(type: "string", description: "Updated notes or context to append when action is 'update_summary'.")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action ('read' or 'update_summary')")
        }

        let convId = await MainActor.run {
            AssistConversationHistory.shared.activeConversationID ?? AssistConversationHistory.shared.startNewConversation().id
        }

        let contextFileURL = await MainActor.run {
            AssistConversationHistory.shared.baseDirectoryURL.appendingPathComponent("\(convId.uuidString).context.md")
        }

        switch action.lowercased() {
        case "read", "view":
            if FileManager.default.fileExists(atPath: contextFileURL.path),
               let text = try? String(contentsOf: contextFileURL, encoding: .utf8) {
                return .success("Conversation Context (\(convId.uuidString)):\n\n\(text)")
            } else {
                return .success("No custom context file found yet for active conversation (\(convId.uuidString)).")
            }

        case "update", "update_summary", "append":
            let notes = input["notes"] as? String ?? ""
            guard !notes.isEmpty else {
                return .failure("Action 'update_summary' requires non-empty 'notes'.")
            }
            var existing = (try? String(contentsOf: contextFileURL, encoding: .utf8)) ?? "# Conversation Context\n\n"
            existing += "\n### Additional Model Context (Updated \(ISO8601DateFormatter().string(from: Date()))):\n\(notes)\n"
            do {
                try existing.write(to: contextFileURL, atomically: true, encoding: .utf8)
                return .success("Successfully updated conversation context file at: \(contextFileURL.path)")
            } catch {
                return .failure("Failed to write conversation context file: \(error.localizedDescription)")
            }

        default:
            return .failure("Unsupported action '\(action)'. Use 'read' or 'update_summary'.")
        }
    }
}
