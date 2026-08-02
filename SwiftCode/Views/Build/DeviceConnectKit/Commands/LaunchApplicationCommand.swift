import Foundation
import OSLog

public struct LaunchApplicationCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "LaunchApplicationCommand")

    public init() {}

    public func execute(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Int32? {
        let devicectlURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let args = [
            "devicectl", "device", "launch", "app",
            "--device", deviceUDID,
            bundleIdentifier
        ]

        Self.logger.info("Launching \(bundleIdentifier) on \(deviceUDID)...")

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: devicectlURL,
                arguments: args
            )

            if res.exitCode == 0 {
                if let range = res.stdout.range(of: "process:"),
                   let pidString = res.stdout[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).first,
                   let pid = Int32(pidString) {
                    return pid
                }
                return 1
            } else {
                Self.logger.error("Launch command failed: \(res.stderr)")
                return nil
            }
        } catch {
            Self.logger.error("Failed to execute launch: \(error.localizedDescription)")
            return nil
        }
    }
}
