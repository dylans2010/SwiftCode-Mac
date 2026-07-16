import Foundation

public struct AssistClearMemoryTool: AssistTool {
    public let id = "mem_clear"
    public let name = "Clear Memory"
    public let description = "Clears all stored information in the memory graph."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        context.memory.clear()
        return .success("Memory cleared.")
    }
}
