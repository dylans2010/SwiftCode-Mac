import Foundation

public struct AssistRetrieveMemoryTool: AssistTool {
    public let id = "mem_retrieve"
    public let name = "Retrieve Memory"
    public let description = "Retrieves information from the long-term memory graph."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Retrieves a value from the long-term memory graph.",
            properties: [
                "key": JSONSchema(type: "string", description: "Memory key to look up.")
            ],
            required: ["key"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let key = input["key"] as? String else {
            return .failure("Missing required parameter: key")
        }

        if let value = context.memory.retrieve(key: key) {
            return .success("Retrieved from memory: \(key)", data: ["value": value])
        } else {
            return .failure("Key not found in memory: \(key)")
        }
    }
}
