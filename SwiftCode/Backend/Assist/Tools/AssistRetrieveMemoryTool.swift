import Foundation

public struct AssistRetrieveMemoryTool: AssistTool {
    public let id = "mem_retrieve"
    public let name = "Retrieve Memory"
    public let description = "Retrieves information from the long-term memory graph."

    public init() {}

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
