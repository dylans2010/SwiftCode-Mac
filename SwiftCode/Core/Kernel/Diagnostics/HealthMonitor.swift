import Foundation

/// Monitors application and Kernel health.
public actor HealthMonitor: KernelService {
    public let id = "com.swiftcode.kernel.health"

    private var healthStates: [String: KernelHealthStatus] = [:]
    private var lastCheck: [String: Date] = [:]

    public init() {}

    public func initialize() async throws {
        print("[Health] Health Monitor initialized.")
    }

    public func reportStatus(_ status: KernelHealthStatus, for componentId: String) {
        healthStates[componentId] = status
        lastCheck[componentId] = Date()

        if status == .failed || status == .degraded {
            LoggingTool.error("[Health] Component \(componentId) reported critical status: \(status.rawValue)")
        }
    }

    public func getOverallHealth() -> KernelHealthStatus {
        if healthStates.values.contains(.failed) { return .failed }
        if healthStates.values.contains(.degraded) { return .degraded }
        if healthStates.values.contains(.warning) { return .warning }
        return .healthy
    }

    public func getFullReport() -> [String: String] {
        var report: [String: String] = [:]
        for (id, status) in healthStates {
            let date = lastCheck[id]?.description ?? "unknown"
            report[id] = "\(status.rawValue) (at \(date))"
        }
        return report
    }
}
