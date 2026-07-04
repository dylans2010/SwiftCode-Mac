import Foundation

public struct AIContextMemoryTool {
    public static let identifier = "ai_context_memory"

    public func run(action: String, data: String?) async throws -> String? {
        return "Memory \(action)ed"
    }
}
