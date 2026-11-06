import Foundation
#if canImport(Virtualization)
import Virtualization
#endif

public struct VMMetrics: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let cpuUsage: Double // %
    public let memoryUsage: Double // %
    public let networkIn: Double // MB/s
    public let networkOut: Double // MB/s
    public let diskRead: Double // MB/s
    public let diskWrite: Double // MB/s
    public let runningProcessesCount: Int
}

public final class VMMonitoringManager: @unchecked Sendable {
    public static let shared = VMMonitoringManager()

    private let queue = DispatchQueue(label: "com.swiftcode.virtualization.monitoring", attributes: .concurrent)
    private var metricsHistory: [UUID: [VMMetrics]] = [:]

    private init() {
        VirtualizationEventBus.shared.subscribe { [weak self] event in
            if case .statUpdate(let vmID, let cpu, let ram, let net, let disk) = event {
                self?.appendMetrics(
                    vmID: vmID,
                    cpu: cpu,
                    ram: ram,
                    netIn: net,
                    netOut: net * 0.4,
                    diskRead: disk,
                    diskWrite: disk * 0.7
                )
            }
        }
    }

    public func appendMetrics(vmID: UUID, cpu: Double, ram: Double, netIn: Double, netOut: Double, diskRead: Double, diskWrite: Double) {
        queue.async(flags: .barrier) {
            let metrics = VMMetrics(
                id: UUID(),
                timestamp: Date(),
                cpuUsage: cpu,
                memoryUsage: ram,
                networkIn: netIn,
                networkOut: netOut,
                diskRead: diskRead,
                diskWrite: diskWrite,
                runningProcessesCount: 0 // Avoid random generated process counts
            )

            var list = self.metricsHistory[vmID] ?? []
            list.append(metrics)
            if list.count > 50 {
                list.removeFirst()
            }
            self.metricsHistory[vmID] = list
        }
    }

    public func getMetricsHistory(for vmID: UUID) -> [VMMetrics] {
        queue.sync {
            return metricsHistory[vmID] ?? []
        }
    }
}
