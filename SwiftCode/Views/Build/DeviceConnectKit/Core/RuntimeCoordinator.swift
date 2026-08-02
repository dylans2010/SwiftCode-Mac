import Foundation
import OSLog

public actor RuntimeCoordinator {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "RuntimeCoordinator")

    private var monitoringTasks: [String: Task<Void, Never>] = [:] // deviceUDID: Task

    public init() {}

    public func startMonitoring(deviceUDID: String, bundleID: String, pid: Int32, onStateChanged: @escaping @Sendable (RuntimeStatus) -> Void, onMetrics: @escaping @Sendable (DeviceMetrics) -> Void) {
        monitoringTasks[deviceUDID]?.cancel()

        monitoringTasks[deviceUDID] = Task { [deviceUDID, bundleID, pid, onStateChanged, onMetrics] in
            onStateChanged(.running)

            while !Task.isCancelled {
                // Simulate periodic metrics query or process validation.
                // In production, real CPU/memory values can be fetched or simulated metrics populated if real APIs fail on sandbox.
                let metrics = DeviceMetrics(
                    cpuUsage: Double.random(in: 1...12),
                    memoryUsage: Double.random(in: 45...85),
                    batteryLevel: 98.0,
                    activeThreads: Int.random(in: 3...9),
                    diskAvailable: 124.5
                )
                onMetrics(metrics)

                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    public func stopMonitoring(deviceUDID: String) {
        monitoringTasks[deviceUDID]?.cancel()
        monitoringTasks.removeValue(forKey: deviceUDID)
    }
}
