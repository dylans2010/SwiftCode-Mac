import Foundation

/// Provides diagnostics and performance metrics.
public actor DiagnosticsProvider: KernelService {
    public let id = "com.swiftcode.kernel.diagnostics"

    private var metrics: [String: Double] = [:]
    private var startTimes: [String: Date] = [:]

    public init() {}

    public func initialize() async throws {
        print("[Diagnostics] Diagnostics Provider initialized.")
    }

    public func startTimer(for name: String) {
        startTimes[name] = Date()
    }

    public func stopTimer(for name: String) {
        guard let start = startTimes[name] else { return }
        let duration = Date().timeIntervalSince(start)
        recordMetric(duration, for: name)
    }

    public func recordMetric(_ value: Double, for name: String) {
        metrics[name] = value
    }

    public func getReport() -> [String: Double] {
        return metrics
    }
}
