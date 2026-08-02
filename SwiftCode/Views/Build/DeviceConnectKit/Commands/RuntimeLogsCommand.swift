import Foundation
import OSLog

public struct RuntimeLogsCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "RuntimeLogsCommand")

    public init() {}

    public func execute(
        deviceUDID: String,
        pid: Int32,
        onLog: @escaping @Sendable (String) -> Void
    ) throws -> Process {
        let devicectlURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let args = [
            "devicectl", "device", "info", "syslog",
            "--device", deviceUDID,
            "--process", String(pid)
        ]

        Self.logger.info("Streaming syslog for device \(deviceUDID), PID \(pid)...")

        return try ProcessRunnerTool.shared.runStreaming(
            executableURL: devicectlURL,
            arguments: args,
            onStdout: { line in
                onLog(line)
            },
            onStderr: { line in
                onLog("[Syslog-Stderr] " + line)
            }
        )
    }
}
