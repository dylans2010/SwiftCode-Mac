import Foundation

public struct MemoryProfilerTool: AgentTool {
    public static let identifier = "memory_profiler"
    public let name = "memory_profiler"
    public let description = "Profiles the memory usage of a process."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "pid": ["type": "integer"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["pid"]
    ]

    public func run(pid: Int32) async throws -> String {
        return "Memory usage data for process \(pid)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let pid = arguments["pid"] as? Int32 else {
            throw AgentError.toolError("Missing pid")
        }
        return try await run(pid: pid)
    }
}
