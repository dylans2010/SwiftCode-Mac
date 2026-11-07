import Foundation

public struct AssistToolCapabilityLookupTool: AssistTool {
    public let id = "tool_capability_lookup"
    public let name = "Tool Capability Lookup"
    public let description = "Looks up a registered tool's capability, risk level, description, and parameter schema from the live registry."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Looks up a tool in the registry.",
            properties: [
                "toolId": JSONSchema(type: "string", description: "Registered tool id, e.g. repo_overview.")
            ],
            required: ["toolId"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let toolId = (input["toolId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !toolId.isEmpty else {
            return .failure("Missing required parameter: toolId")
        }
        guard let tool = AssistToolRegistry.shared.getTool(toolId) else {
            return .failure("No registered tool with id '\(toolId)'.")
        }
        let schema = tool.parametersSchema
        let required = (schema.required ?? []).joined(separator: ", ")
        let props = (schema.properties?.keys.sorted() ?? []).joined(separator: ", ")
        let output = [
            "Tool: \(tool.id) — \(tool.name)",
            "Capability: \(tool.capability)",
            "Risk level: \(tool.riskLevel)",
            "Read-only: \(tool.isReadOnly), Mutating: \(tool.isMutating)",
            "Description: \(tool.description)",
            "Parameters: \(props.isEmpty ? "(none)" : props)",
            "Required: \(required.isEmpty ? "(none)" : required)",
            "Estimated cost: \(tool.estimatedCost)"
        ].joined(separator: "\n")
        return .success(output, data: [
            "toolId": tool.id, "capability": "\(tool.capability)",
            "riskLevel": "\(tool.riskLevel)", "required": required
        ])
    }
}
