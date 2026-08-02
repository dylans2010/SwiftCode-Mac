import Foundation
import OSLog

public struct StopApplicationCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "StopApplicationCommand")

    public init() {}

    public func execute(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Bool {
        let devicectlURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let args = [
            "devicectl", "device", "terminate", "app",
            "--device", deviceUDID,
            bundleIdentifier
        ]

        Self.logger.info("Stopping \(bundleIdentifier) on \(deviceUDID)...")

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: devicectlURL,
                arguments: args
            )
            return res.exitCode == 0
        } catch {
            Self.logger.error("Failed to execute stop command: \(error.localizedDescription)")
            return false
        }
    }
}
