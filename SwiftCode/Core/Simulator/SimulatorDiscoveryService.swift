import Foundation
import os

public actor SimulatorDiscoveryService {
    private let simctlService = SimctlService()
    private let logger = Logger(subsystem: "com.swiftcode.simulator", category: "DiscoveryService")

    public init() {}

    public func discoverActiveSimulators() async throws -> (devices: [SimulatorDevice], runtimes: [SimulatorRuntime]) {
        logger.info("[BEGIN] Discovering simulators and runtimes")
        let startTime = Date()

        do {
            let result = try await simctlService.fetchDevicesAndRuntimes()
            let duration = Date().timeIntervalSince(startTime)
            logger.info("[END] Discovered \(result.devices.count) devices and \(result.runtimes.count) runtimes in \(duration)s")
            return result
        } catch {
            logger.error("[FAILED] Simulator discovery failed: \(error.localizedDescription)")
            throw error
        }
    }
}
