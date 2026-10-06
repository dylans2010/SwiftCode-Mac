import Foundation

public struct AssistRetrieveMemoryTool: AssistTool {
    public let id = "mem_retrieve"
    public let name = "Retrieve Memory"
    public let description = "Retrieves information from the long-term memory graph."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Retrieves stored information from long-term memory graph.",
            properties: [
                "key": JSONSchema(type: "string", description: "Unique memory key identifier to query.")
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
