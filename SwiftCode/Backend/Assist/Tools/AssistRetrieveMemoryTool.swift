import Foundation

public struct AssistRetrieveMemoryTool: AssistTool {
    public let id = "retrieve_memory"
    public let name = "Retrieve Memory"
    public let description = "Returns the contents of the UserMemory.md file containing user preferences, patterns, and durable facts."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Returns the contents of the UserMemory.md file.",
            properties: [
                "query": JSONSchema(type: "string", description: "Optional query to search or filter specific memory entries.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard await AssistMemoryStore.shared.isMemoryEnabled else {
            return .failure("User has Memory module OFF.")
        }

        let query = (input["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = await AssistMemoryStore.shared.retrieve(query: query)

        return .success(content, data: ["content": content])
    }
}
