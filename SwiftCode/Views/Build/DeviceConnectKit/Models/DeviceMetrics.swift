import Foundation

public struct DeviceMetrics: Codable, Sendable, Hashable {
    public var cpuUsage: Double // percentage
    public var memoryUsage: Double // megabytes
    public var batteryLevel: Double // percentage
    public var activeThreads: Int
    public var diskAvailable: Double // gigabytes

    public init(
        cpuUsage: Double = 0,
        memoryUsage: Double = 0,
        batteryLevel: Double = 100,
        activeThreads: Int = 1,
        diskAvailable: Double = 0
    ) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.batteryLevel = batteryLevel
        self.activeThreads = activeThreads
        self.diskAvailable = diskAvailable
    }
}
