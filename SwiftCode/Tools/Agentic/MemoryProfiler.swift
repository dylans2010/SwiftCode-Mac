import Foundation

public struct MemoryProfilerTool {
    public static let identifier = "memory_profiler"

    public func run(pid: Int32) async throws -> String {
        return "Memory usage data for process \(pid)"
    }
}
