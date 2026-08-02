import Foundation
import OSLog

public struct InstallApplicationCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "InstallApplicationCommand")

    public init() {}

    public func execute(
        deviceUDID: String,
        appBundleURL: URL,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> Bool {
        let devicectlURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let args = [
            "devicectl", "device", "install", "app",
            "--device", deviceUDID,
            appBundleURL.path
        ]

        Self.logger.info("Installing app to device \(deviceUDID)...")

        do {
            let success = try await ProcessRunnerTool.shared.runStreamingAsync(
                executableURL: devicectlURL,
                arguments: args,
                onStdout: { line in
                    onProgress(line)
                },
                onStderr: { line in
                    onProgress("[Error] " + line)
                }
            )
            return success
        } catch {
            Self.logger.error("Failed to run devicectl install: \(error.localizedDescription)")
            return false
        }
    }
}
