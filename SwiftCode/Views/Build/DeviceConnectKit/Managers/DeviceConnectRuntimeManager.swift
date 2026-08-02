import Foundation
import Observation

@Observable
@MainActor
public final class DeviceConnectRuntimeManager {
    public static let shared = DeviceConnectRuntimeManager()

    public private(set) var runtimeStatus: RuntimeStatus = .idle
    public private(set) var metrics: DeviceMetrics = DeviceMetrics()
    public private(set) var activePID: Int32? = nil

    private init() {}

    public func updateRuntimeStatus(_ status: RuntimeStatus) {
        self.runtimeStatus = status
    }

    public func updateMetrics(_ metrics: DeviceMetrics) {
        self.metrics = metrics
    }

    public func startMonitoring(deviceUDID: String, bundleID: String, pid: Int32) {
        self.activePID = pid
        self.runtimeStatus = .running

        let coordinator = RuntimeCoordinator()
        Task {
            await coordinator.startMonitoring(
                deviceUDID: deviceUDID,
                bundleID: bundleID,
                pid: pid,
                onStateChanged: { [weak self] status in
                    Task { @MainActor [weak self] in
                        self?.runtimeStatus = status
                    }
                },
                onMetrics: { [weak self] nextMetrics in
                    Task { @MainActor [weak self] in
                        self?.metrics = nextMetrics
                    }
                }
            )
        }
    }

    public func stopMonitoring(deviceUDID: String) {
        self.activePID = nil
        self.runtimeStatus = .idle
    }
}
