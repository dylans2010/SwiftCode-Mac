import Foundation

public struct SimulatorSnapshot: Sendable {
    public let runtimes: [SimulatorRuntime]
    public let devices: [SimulatorDevice]
    public let bootedDeviceIDs: Set<String>
    public let generatedAt: Date
    public let discoveryDuration: Duration

    public var orphanedDevices: [SimulatorDevice] {
        devices.filter { d in
            !runtimes.contains { $0.identifier == d.runtimeIdentifier }
        }
    }

    public init(
        runtimes: [SimulatorRuntime],
        devices: [SimulatorDevice],
        bootedDeviceIDs: Set<String>,
        generatedAt: Date,
        discoveryDuration: Duration
    ) {
        self.runtimes = runtimes
        self.devices = devices
        self.bootedDeviceIDs = bootedDeviceIDs
        self.generatedAt = generatedAt
        self.discoveryDuration = discoveryDuration
    }
}
