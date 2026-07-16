import Foundation

public struct AssistStoreMemoryTool: AssistTool {
    public let id = "mem_store"
    public let name = "Store Memory"
    public let description = "Stores information in the long-term memory graph."

    public init() {}

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
