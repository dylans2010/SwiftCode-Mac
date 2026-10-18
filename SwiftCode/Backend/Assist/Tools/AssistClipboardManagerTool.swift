//
//  AssistClipboardManagerTool.swift
//  SwiftCode
//

import Foundation
import AppKit

public struct AssistClipboardManagerTool: AssistTool {
    public let id = "clipboard_manager_tool"
    public let name = "Clipboard Manager"
    public let description = "Reads text from or copies content to the macOS system clipboard (NSPasteboard)."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Interact with the macOS system pasteboard (read or copy text).",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'read' (read current clipboard) or 'copy' (write content to clipboard)."),
                "content": JSONSchema(type: "string", description: "Text content to copy when action is 'copy'.")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action")
        }

        switch action.lowercased() {
        case "read", "get":
            let current = await MainActor.run {
                NSPasteboard.general.string(forType: .string) ?? ""
            }
            if current.isEmpty {
                return .success("Clipboard is currently empty.")
            } else {
                let preview = String(current.prefix(500))
                return .success("Current Clipboard Content (\(current.count) chars):\n\n```\n\(preview)\n```")
            }

        case "copy", "write", "set":
            guard let content = input["content"] as? String else {
                return .failure("Action 'copy' requires 'content'.")
            }
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
            }
            return .success("Successfully copied \(content.count) characters to the system clipboard.")

        default:
            return .failure("Unsupported action '\(action)'. Supported: 'read', 'copy'.")
        }
    }
}
