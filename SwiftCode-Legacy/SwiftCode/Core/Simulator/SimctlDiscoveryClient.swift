import Foundation
import os

public struct SimctlDiscoveryResult: Sendable {
    public let runtimes: [RuntimeDTO]
    public let devices: [String: [DeviceDTO]]
    public let deviceTypes: [DeviceTypeDTO]
    public let pairs: [String: PairDTO]
}

public actor SimctlDiscoveryClient {
    public static let shared = SimctlDiscoveryClient()

    private init() {}

    public func fetchDiscoveryData() async throws -> SimctlDiscoveryResult {
        Logger.discovery.info("[DISCOVERY-CLIENT] Fetching simulator metadata from simctl concurrently...")

        // Construct command specs
        let runtimesSpec = CommandSpec(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "list", "runtimes", "--json"]
        )
        let devicesSpec = CommandSpec(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "list", "devices", "--json"]
        )
        let deviceTypesSpec = CommandSpec(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "list", "devicetypes", "--json"]
        )
        let pairsSpec = CommandSpec(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "list", "pairs", "--json"]
        )

        // Execute concurrently using structured async let bindings
        async let runtimesRecord = CommandExecutionEngine.shared.execute(runtimesSpec)
        async let devicesRecord = CommandExecutionEngine.shared.execute(devicesSpec)
        async let deviceTypesRecord = CommandExecutionEngine.shared.execute(deviceTypesSpec)
        async let pairsRecord = CommandExecutionEngine.shared.execute(pairsSpec)

        // Await each of them, decoding with high fault-tolerance
        let decodedRuntimes = await decodeRuntimes(from: runtimesRecord)
        let decodedDevices = await decodeDevices(from: devicesRecord)
        let decodedDeviceTypes = await decodeDeviceTypes(from: deviceTypesRecord)
        let decodedPairs = await decodePairs(from: pairsRecord)

        // Gating conditions: Runtimes and devices are absolutely required for a successful basic loaded state.
        // If runtimes and devices are both completely missing or failed, throw a general error.
        if decodedRuntimes.isEmpty && decodedDevices.isEmpty {
            Logger.discovery.error("[DISCOVERY-CLIENT] Critical failure: Both runtimes and devices list are empty or failed to parse.")
            throw NSError(
                domain: "SimctlDiscoveryClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse both runtimes and devices from simctl list."]
            )
        }

        Logger.discovery.info("[DISCOVERY-CLIENT] Successfully resolved runtimes count: \(decodedRuntimes.count), devices groups: \(decodedDevices.keys.count)")

        return SimctlDiscoveryResult(
            runtimes: decodedRuntimes,
            devices: decodedDevices,
            deviceTypes: decodedDeviceTypes,
            pairs: decodedPairs
        )
    }

    private func decodeRuntimes(from record: CommandExecutionRecord) async -> [RuntimeDTO] {
        guard record.exitCode == 0 else {
            Logger.decode.error("[DISCOVERY-CLIENT] runtimes simctl command failed with exit code \(record.exitCode)")
            return []
        }
        do {
            let response = try JSONDecoder().decode(SimctlListResponse.self, from: record.stdout)
            return response.runtimes ?? []
        } catch {
            logDecodingError(error, data: record.stdout, type: "runtimes")
            return []
        }
    }

    private func decodeDevices(from record: CommandExecutionRecord) async -> [String: [DeviceDTO]] {
        guard record.exitCode == 0 else {
            Logger.decode.error("[DISCOVERY-CLIENT] devices simctl command failed with exit code \(record.exitCode)")
            return [:]
        }
        do {
            let response = try JSONDecoder().decode(SimctlListResponse.self, from: record.stdout)
            return response.devices ?? [:]
        } catch {
            logDecodingError(error, data: record.stdout, type: "devices")
            return [:]
        }
    }

    private func decodeDeviceTypes(from record: CommandExecutionRecord) async -> [DeviceTypeDTO] {
        guard record.exitCode == 0 else {
            Logger.decode.error("[DISCOVERY-CLIENT] devicetypes simctl command failed with exit code \(record.exitCode)")
            return []
        }
        do {
            let response = try JSONDecoder().decode(SimctlListResponse.self, from: record.stdout)
            return response.devicetypes ?? []
        } catch {
            logDecodingError(error, data: record.stdout, type: "devicetypes")
            return []
        }
    }

    private func decodePairs(from record: CommandExecutionRecord) async -> [String: PairDTO] {
        guard record.exitCode == 0 else {
            Logger.decode.error("[DISCOVERY-CLIENT] pairs simctl command failed with exit code \(record.exitCode)")
            return [:]
        }
        do {
            let response = try JSONDecoder().decode(SimctlListResponse.self, from: record.stdout)
            return response.pairs ?? [:]
        } catch {
            logDecodingError(error, data: record.stdout, type: "pairs")
            return [:]
        }
    }

    private func logDecodingError(_ error: Error, data: Data, type: String) {
        let byteCount = data.count
        if let decodingError = error as? DecodingError {
            var pathStr = "root"
            switch decodingError {
            case .typeMismatch(_, let context),
                 .valueNotFound(_, let context),
                 .keyNotFound(_, let context),
                 .dataCorrupted(let context):
                pathStr = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            @unknown default:
                break
            }
            Logger.decode.error("[DISCOVERY-CLIENT] \(type) decoding error path '\(pathStr)' on payload size of \(byteCount) bytes: \(error.localizedDescription)")
        } else {
            Logger.decode.error("[DISCOVERY-CLIENT] \(type) decoding failed (payload size: \(byteCount) bytes): \(error.localizedDescription)")
        }
    }
}
