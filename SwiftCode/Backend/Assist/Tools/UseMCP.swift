import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.mcp", category: "UseMCP")

// MARK: - MCP Execution Metadata for Timeline Rendering

public struct MCPExecutionMetadata: Codable, Sendable, Identifiable {
    public let id: UUID
    public let serverName: String
    public let toolName: String
    public let arguments: String
    public var output: String
    public var success: Bool
    public var isExecuting: Bool
    public var duration: TimeInterval
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        serverName: String,
        toolName: String,
        arguments: String,
        output: String,
        success: Bool = false,
        isExecuting: Bool = true,
        duration: TimeInterval = 0.0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.serverName = serverName
        self.toolName = toolName
        self.arguments = arguments
        self.output = output
        self.success = success
        self.isExecuting = isExecuting
        self.duration = duration
        self.timestamp = timestamp
    }
}

// MARK: - UseMCP Assist Tool

@MainActor
public final class UseMCP: AssistTool {
    public let id = "use_mcp"
    public let name = "Execute MCP Tool"
    public let description = "Enumerate configured MCP servers, negotiate server capabilities, and execute a tool."

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Execute a tool on a connected Model Context Protocol (MCP) server.",
            properties: [
                "serverName": JSONSchema(
                    type: "string",
                    description: "The display name of the connected MCP server."
                ),
                "toolName": JSONSchema(
                    type: "string",
                    description: "The name of the tool to execute on the selected MCP server."
                ),
                "arguments": JSONSchema(
                    type: "string",
                    description: "A JSON-serialized object string containing the arguments to pass to the MCP tool."
                )
            ],
            required: ["serverName", "toolName", "arguments"]
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let serverName = input["serverName"] as? String,
              let toolName = input["toolName"] as? String,
              let argsString = input["arguments"] as? String else {
            return .failure("Missing required arguments (serverName, toolName, arguments).")
        }

        let manager = MCPServerManager.shared
        guard let server = manager.servers.first(where: { $0.displayName.lowercased() == serverName.lowercased() || $0.id.uuidString == serverName }) else {
            return .failure("MCP Server '\(serverName)' not found or not configured.")
        }

        guard server.status == .connected else {
            return .failure("MCP Server '\(server.displayName)' is disconnected. Please connect the server in settings before executing tools.")
        }

        // Parse arguments JSON
        let data = argsString.data(using: .utf8) ?? Data()
        guard let decodedArgsObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Arguments must be a valid JSON-serialized object string.")
        }

        var mappedArgs: [String: JSONValue] = [:]
        for (k, v) in decodedArgsObj {
            mappedArgs[k] = convertToJSONValue(v)
        }

        let startTime = Date()
        let msgId = UUID()

        let initialMetadata = MCPExecutionMetadata(
            id: msgId,
            serverName: server.displayName,
            toolName: toolName,
            arguments: argsString,
            output: "Initializing execution on '\(server.displayName)'...",
            success: false,
            isExecuting: true,
            duration: 0.0,
            timestamp: Date()
        )

        var mcpMessage = AssistMessage(role: .system, content: "Running MCP Tool...", attachments: nil)
        mcpMessage.mcpExecution = initialMetadata

        // Append message to AssistManager
        AssistManager.shared.messages.append(mcpMessage)

        func updateLiveOutput(output: String, isExecuting: Bool = true, success: Bool = false) {
            let duration = Date().timeIntervalSince(startTime)
            if let idx = AssistManager.shared.messages.firstIndex(where: { $0.id == mcpMessage.id }) {
                var updated = AssistManager.shared.messages[idx]
                updated.mcpExecution = MCPExecutionMetadata(
                    id: msgId,
                    serverName: server.displayName,
                    toolName: toolName,
                    arguments: argsString,
                    output: output,
                    success: success,
                    isExecuting: isExecuting,
                    duration: duration,
                    timestamp: startTime
                )
                AssistManager.shared.messages[idx] = updated
            }
        }

        updateLiveOutput(output: "Connecting & invoking tool '\(toolName)' on '\(server.displayName)'...")

        do {
            let response = try await manager.callTool(serverID: server.id, name: toolName, arguments: mappedArgs)

            let outputText = response.content.compactMap { $0.text }.joined(separator: "\n")

            if response.isError {
                updateLiveOutput(output: "Execution failed:\n\(outputText)", isExecuting: false, success: false)
                return .failure("MCP Tool execution failed: \(outputText)")
            } else {
                updateLiveOutput(output: outputText, isExecuting: false, success: true)
                return .success(outputText)
            }
        } catch {
            updateLiveOutput(output: "Error: \(error.localizedDescription)", isExecuting: false, success: false)
            return .failure("Failed to execute MCP tool: \(error.localizedDescription)")
        }
    }

    private func convertToJSONValue(_ val: Any) -> JSONValue {
        if val is NSNull { return .null }
        if let str = val as? String { return .string(str) }
        if let num = val as? Double { return .number(num) }
        if let num = val as? Int { return .number(Double(num)) }
        if let bool = val as? Bool { return .boolean(bool) }
        if let arr = val as? [Any] {
            return .array(arr.map { convertToJSONValue($0) })
        }
        if let dict = val as? [String: Any] {
            var obj: [String: JSONValue] = [:]
            for (k, v) in dict {
                obj[k] = convertToJSONValue(v)
            }
            return .object(obj)
        }
        return .null
    }
}
