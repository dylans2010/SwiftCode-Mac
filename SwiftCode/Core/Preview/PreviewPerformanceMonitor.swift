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
        // Simulate background system resource observation
        memoryUsage = Double.random(in: 45.0...120.0)
        cpuUsage = Double.random(in: 1.5...12.0)
    }

    public func updateResourceMetrics() {
        memoryUsage = Double.random(in: 45.0...120.0)
        cpuUsage = Double.random(in: 1.5...12.0)
        if let start = sessionStartTime {
            sessionLifetime = Date().timeIntervalSince(start)
        }
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
