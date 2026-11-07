import Foundation

@MainActor
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
        let memoryGrowth: Double
    }

    public init(context: AssistContext) {
        self.context = context
    }

    public func startMonitoring() {
        startTime = Date()
        recordMemorySnapshot()
    }

    public func recordToolExecution(toolId: String, duration: TimeInterval) {
        if stepExecutionTimes[toolId] == nil {
            stepExecutionTimes[toolId] = []
        }
        stepExecutionTimes[toolId]?.append(duration)
    }

    public func recordMemorySnapshot() {
        let usedMemory = getMemoryUsage()
        memorySnapshots.append(MemorySnapshot(timestamp: Date(), usedMemory: usedMemory))
    }

    public func getMetrics() -> BehaviorMetrics {
        let totalRuntime = Date().timeIntervalSince(startTime ?? Date())

        let allExecutionTimes = stepExecutionTimes.values.flatMap { $0 }
        let averageIterationTime = allExecutionTimes.isEmpty ? 0 : allExecutionTimes.reduce(0, +) / Double(allExecutionTimes.count)

        var slowestTool: String?
        var maxAverage: TimeInterval = 0
        for (toolId, times) in stepExecutionTimes {
            let avg = times.reduce(0, +) / Double(times.count)
            if avg > maxAverage {
                maxAverage = avg
                slowestTool = toolId
            }
        }

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

    public func isHealthy() async -> Bool {
        let metrics = getMetrics()

        if metrics.memoryGrowth > 1_000_000 {
            await context.logger.warning("Possible memory leak detected: \(Int(metrics.memoryGrowth)) bytes/sec", toolId: "BehaviorMonitor")
            return false
        }

        if metrics.totalRuntime > 3600 {
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
