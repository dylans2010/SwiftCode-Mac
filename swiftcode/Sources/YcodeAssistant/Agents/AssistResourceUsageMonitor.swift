import Foundation

@MainActor
public final class AssistResourceUsageMonitor {
    private let context: AssistContext
    private var startMemory: UInt64 = 0
    private var peakMemory: UInt64 = 0
    private var startTime: Date?

    public struct ResourceMetrics {
        let memoryUsed: UInt64
        let peakMemory: UInt64
        let memoryDelta: Int64
        let cpuTime: TimeInterval?
        let elapsed: TimeInterval
    }

    public init(context: AssistContext) {
        self.context = context
    }

    public func startMonitoring() {
        startMemory = getMemoryUsage()
        peakMemory = startMemory
        startTime = Date()
    }

    public func updateMetrics() {
        let current = getMemoryUsage()
        if current > peakMemory {
            peakMemory = current
        }
    }

    public func getCurrentMetrics() -> ResourceMetrics {
        let currentMemory = getMemoryUsage()
        let delta = Int64(currentMemory) - Int64(startMemory)
        let elapsed = Date().timeIntervalSince(startTime ?? Date())

        return ResourceMetrics(
            memoryUsed: currentMemory,
            peakMemory: peakMemory,
            memoryDelta: delta,
            cpuTime: nil,
            elapsed: elapsed
        )
    }

    public func isResourceUsageHealthy() async -> Bool {
        let metrics = getCurrentMetrics()

        if metrics.memoryDelta > 500_000_000 {
            await context.logger.error("Excessive memory usage: \(metrics.memoryDelta / 1_000_000)MB delta", toolId: "ResourceMonitor")
            return false
        }

        if metrics.elapsed > 7200 {
            await context.logger.error("Excessive runtime: \(Int(metrics.elapsed))s", toolId: "ResourceMonitor")
            return false
        }

        return true
    }

    public func logResourceSummary() async {
        let metrics = getCurrentMetrics()
        await context.logger.info("""
        Resource Usage:
        - Current memory: \(metrics.memoryUsed / 1_000_000)MB
        - Peak memory: \(metrics.peakMemory / 1_000_000)MB
        - Memory delta: \(metrics.memoryDelta / 1_000_000)MB
        - CPU time: not tracked (untracked, not 0s)
        - Elapsed time: \(Int(metrics.elapsed))s
        """, toolId: "ResourceMonitor")
    }

    private func getMemoryUsage() -> UInt64 {
#if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
#else
        guard let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else { return 0 }
        for line in status.split(separator: "\n") where line.hasPrefix("VmRSS:") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count >= 2, let kilobytes = UInt64(fields[1]) {
                return kilobytes * 1024
            }
        }
        return 0
#endif
    }
}
