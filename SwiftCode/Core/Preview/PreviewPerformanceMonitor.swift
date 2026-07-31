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

    private var compileTimes: [Double] = []
    private var renderTimes: [Double] = []
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

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
}
