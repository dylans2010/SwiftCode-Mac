import Foundation

/// Monitors runtime behavior of autonomous execution
public final class AssistRuntimeBehaviorMonitor {
    private let context: AssistContext
    private var startTime: Date?
    private var stepExecutionTimes: [String: [TimeInterval]] = [:]
    private var memorySnapshots: [MemorySnapshot] = []

    public struct MemorySnapshot {
        let timestamp: Date
        let usedMemory: UInt64
    }

    public struct BehaviorMetrics {
        let totalRuntime: TimeInterval
        let averageIterationTime: TimeInterval
        let slowestTool: String?
        let memoryGrowth: Double // bytes per second
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Starts monitoring
    public func startMonitoring() {
        startTime = Date()
        recordMemorySnapshot()
    }

    /// Records execution time for a tool
    public func recordToolExecution(toolId: String, duration: TimeInterval) {
        if stepExecutionTimes[toolId] == nil {
            stepExecutionTimes[toolId] = []
        }
        stepExecutionTimes[toolId]?.append(duration)
    }

    /// Records current memory usage
    public func recordMemorySnapshot() {
        let usedMemory = getMemoryUsage()
        memorySnapshots.append(MemorySnapshot(timestamp: Date(), usedMemory: usedMemory))
    }

    /// Gets current behavior metrics
    public func getMetrics() -> BehaviorMetrics {
        let totalRuntime = Date().timeIntervalSince(startTime ?? Date())

        // Calculate average iteration time
        let allExecutionTimes = stepExecutionTimes.values.flatMap { $0 }
        let averageIterationTime = allExecutionTimes.isEmpty ? 0 : allExecutionTimes.reduce(0, +) / Double(allExecutionTimes.count)

        // Find slowest tool
        var slowestTool: String?
        var maxAverage: TimeInterval = 0
        for (toolId, times) in stepExecutionTimes {
            let avg = times.reduce(0, +) / Double(times.count)
            if avg > maxAverage {
                maxAverage = avg
                slowestTool = toolId
            }
        }

        // Calculate memory growth rate
        var memoryGrowth: Double = 0
        if memorySnapshots.count >= 2 {
            let first = memorySnapshots.first!
            let last = memorySnapshots.last!
            let timeDiff = last.timestamp.timeIntervalSince(first.timestamp)
            let memoryDiff = Double(last.usedMemory) - Double(first.usedMemory)
            memoryGrowth = timeDiff > 0 ? memoryDiff / timeDiff : 0
        }

        return BehaviorMetrics(
            totalRuntime: totalRuntime,
            averageIterationTime: averageIterationTime,
            slowestTool: slowestTool,
            memoryGrowth: memoryGrowth
        )
    }

    /// Checks if behavior is healthy
    public func isHealthy() async -> Bool {
        let metrics = getMetrics()

        // Check for memory leak
        if metrics.memoryGrowth > 1_000_000 { // 1MB per second
            await context.logger.warning("Possible memory leak detected: \(Int(metrics.memoryGrowth)) bytes/sec", toolId: "BehaviorMonitor")
            return false
        }

        // Check for excessive runtime
        if metrics.totalRuntime > 3600 { // 1 hour
            await context.logger.warning("Excessive runtime: \(Int(metrics.totalRuntime))s", toolId: "BehaviorMonitor")
            return false
        }

        return true
    }

    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
}
