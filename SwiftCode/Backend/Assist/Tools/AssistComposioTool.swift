import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.composio", category: "AssistComposioTool")

@MainActor
public final class AssistComposioTool: AssistTool {
    public let id = "use_composio"
    public let name = "Execute Composio Tool"
    public let description = "Execute external connected tools (GitHub, Slack, Google Calendar, Jira, Linear, Gmail, etc.) via Composio Platform or CLI."

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Execute a tool on an external integration connected through Composio.",
            properties: [
                "toolSlug": JSONSchema(
                    type: "string",
                    description: "The slug of the Composio tool to execute (e.g. 'GITHUB_GET_THE_AUTHENTICATED_USER', 'GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER', 'GITHUB_CREATE_AN_ISSUE', 'SLACK_SEND_A_MESSAGE_TO_A_SLACK_CHANNEL')."
                ),
                "arguments": JSONSchema(
                    type: "string",
                    description: "A JSON-serialized object string containing the arguments to pass to the tool."
                )
            ],
            required: ["toolSlug", "arguments"]
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let toolSlug = input["toolSlug"] as? String else {
            return .failure("Missing required parameter: toolSlug")
        }

        let argsString: String
        if let str = input["arguments"] as? String {
            argsString = str
        } else if let dict = input["arguments"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let str = String(data: data, encoding: .utf8) {
            argsString = str
        } else {
            argsString = "{}"
        }

        let service = ComposioService.shared
        let startTime = Date()
        let msgId = UUID()

        let toolkitName = toolSlug.components(separatedBy: "_").first?.lowercased() ?? "general"

        let initialMetadata = ComposioExecutionMetadata(
            id: msgId,
            toolkit: toolkitName,
            toolSlug: toolSlug,
            arguments: argsString,
            output: "Initializing execution for tool '\(toolSlug)'...",
            logId: nil,
            success: false,
            isExecuting: true,
            duration: 0.0,
            timestamp: Date()
        )

        var composioMessage = AssistMessage(role: .system, content: "Running Composio Tool...", attachments: nil)
        composioMessage.composioExecution = initialMetadata

        AssistManager.shared.messages.append(composioMessage)

        func updateLiveOutput(output: String, isExecuting: Bool = true, success: Bool = false, logId: String? = nil) {
            let duration = Date().timeIntervalSince(startTime)
            if let idx = AssistManager.shared.messages.firstIndex(where: { $0.id == composioMessage.id }) {
                var updated = AssistManager.shared.messages[idx]
                updated.composioExecution = ComposioExecutionMetadata(
                    id: msgId,
                    toolkit: toolkitName,
                    toolSlug: toolSlug,
                    arguments: argsString,
                    output: output,
                    logId: logId,
                    success: success,
                    isExecuting: isExecuting,
                    duration: duration,
                    timestamp: startTime
                )
                AssistManager.shared.messages[idx] = updated
            }
        }

        updateLiveOutput(output: "Executing '\(toolSlug)' through Composio...")

        do {
            let result = try await service.executeTool(slug: toolSlug, argumentsJSON: argsString)

            if result.success {
                updateLiveOutput(output: result.output, isExecuting: false, success: true, logId: result.logId)
                return .success(result.output)
            } else {
                updateLiveOutput(output: result.output, isExecuting: false, success: false, logId: result.logId)
                return .failure("Composio execution failed: \(result.output)")
            }
        } catch {
            updateLiveOutput(output: "Error: \(error.localizedDescription)", isExecuting: false, success: false)
            return .failure("Failed to execute Composio tool: \(error.localizedDescription)")
        }
    }
}
