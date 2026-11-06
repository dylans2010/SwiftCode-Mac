// Adapted from SwiftCode-Legacy SwiftCode/Core/Preview/PreviewPerformanceMonitor.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
// Adaptation note: Legacy sampled random memory/CPU numbers; replaced with explicit real-measurement recording (recordResourceMetrics).
import Foundation
import Observation

@Observable
@MainActor
public final class PreviewPerformanceMonitor {
    public static let shared = PreviewPerformanceMonitor()

    public var averageCompileTime: Double = 0.0
    public var averageRenderTime: Double = 0.0
    public var totalRenders: Int = 0
    public var cacheHitRate: Double = 0.0

    // Enhanced metrics for production diagnostics
    public var runtimeStartupTime: Double = 0.0
    public var sessionLifetime: Double = 0.0
    public var memoryUsage: Double = 0.0 // in MBs
    public var cpuUsage: Double = 0.0 // in percentage
    public var renderingFailures: Int = 0
    public var runtimeExceptions: Int = 0

    private var compileTimes: [Double] = []
    private var renderTimes: [Double] = []
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var sessionStartTime: Date?

    private init() {}

    public func recordCompileTime(_ seconds: Double) {
        compileTimes.append(seconds)
        averageCompileTime = compileTimes.reduce(0, +) / Double(compileTimes.count)
    }

    public func recordRenderTime(_ seconds: Double) {
        renderTimes.append(seconds)
        averageRenderTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
        totalRenders += 1
    }

    public func recordCacheLookup(isHit: Bool) {
        if isHit {
            cacheHits += 1
        } else {
            cacheMisses += 1
        }
        let total = cacheHits + cacheMisses
        cacheHitRate = total > 0 ? Double(cacheHits) / Double(total) : 0.0
    }

    public func startSession() {
        sessionStartTime = Date()
        runtimeExceptions = 0
        renderingFailures = 0
        // Resource usage is unknown until a real measurement is recorded
        // via recordResourceMetrics(_:). Legacy sampled random numbers
        // here; that fiction is removed in this port.
        memoryUsage = 0
        cpuUsage = 0
    }

    public func updateResourceMetrics() {
        if let start = sessionStartTime {
            sessionLifetime = Date().timeIntervalSince(start)
        }
    }

    /// Records a real resource measurement (e.g. from `task_info` or the
    /// host process sampler). Memory in MB, CPU as a percentage.
    public func recordResourceMetrics(memoryUsageMB: Double, cpuUsagePercent: Double) {
        memoryUsage = memoryUsageMB
        cpuUsage = cpuUsagePercent
    }

    public func recordFailure() {
        renderingFailures += 1
        PreviewDiagnostics.shared.addLog(category: "error", message: "Recorded active rendering failure.")
    }

    public func recordException(_ details: String) {
        runtimeExceptions += 1
        PreviewDiagnostics.shared.addLog(category: "error", message: "Runtime exception encountered: \(details)")
    }
}
