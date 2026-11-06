import Foundation

public struct AssistStoreMemoryTool: AssistTool {
    public let id = "mem_store"
    public let name = "Store Memory"
    public let description = "Stores information in the long-term memory graph."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Stores a value in the long-term memory graph, overwriting any existing entry for the key.",
            properties: [
                "key": JSONSchema(type: "string", description: "Memory key to store under."),
                "value": JSONSchema(type: "string", description: "Value to store.")
            ],
            required: ["key", "value"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let key = input["key"] as? String else {
            return .failure("Missing required parameter: key")
        }
        guard let value = input["value"] as? String else {
            return .failure("Missing required parameter: value")
        }

        context.memory.store(key: key, value: value)
        return .success("Stored in memory: \(key)")
    }
}
