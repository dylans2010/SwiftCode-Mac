import Foundation
import OSLog

public struct StopApplicationCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "StopApplicationCommand")

    public init() {}

    public func execute(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Bool {
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        let isSim = await isSimulator(udid: deviceUDID)
        if isSim {
            let res = try? await ProcessRunnerTool.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "terminate", deviceUDID, bundleIdentifier]
            )
            return res?.exitCode == 0
        }

        let args = [
            "devicectl", "device", "terminate", "app",
            "--device", deviceUDID,
            bundleIdentifier
        ]

        Self.logger.info("Stopping \(bundleIdentifier) on \(deviceUDID)...")

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: xcrunURL,
                arguments: args
            )
            if res.exitCode == 0 {
                return true
            }
            // Fallback attempt
            let simRes = try? await ProcessRunnerTool.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "terminate", deviceUDID, bundleIdentifier]
            )
            return simRes?.exitCode == 0
        } catch {
            Self.logger.error("Failed to execute stop command: \(error.localizedDescription)")
            let simRes = try? await ProcessRunnerTool.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "terminate", deviceUDID, bundleIdentifier]
            )
            return simRes?.exitCode == 0
        }
    }

    private func isSimulator(udid: String) async -> Bool {
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        if let result = try? await ProcessRunnerTool.shared.run(
            executableURL: xcrunURL,
            arguments: ["simctl", "list", "devices", "-j"]
        ), result.exitCode == 0 {
            return result.stdout.contains(udid)
        }
        return false
    }
}
