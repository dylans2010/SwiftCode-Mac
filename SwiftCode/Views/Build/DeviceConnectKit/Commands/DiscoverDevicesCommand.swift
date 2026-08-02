import Foundation
import OSLog

public struct DiscoverDevicesCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "DiscoverDevicesCommand")

    public init() {}

    public func execute() async throws -> [ConnectedDevice] {
        let executable = URL(fileURLWithPath: "/usr/bin/xcrun")
        let args = ["xcdevice", "list"]

        Self.logger.info("Executing xcrun xcdevice list...")
        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: executable,
                arguments: args
            )

            if result.exitCode == 0 {
                return DeviceParser.parseXCDeviceList(result.stdout)
            } else {
                Self.logger.error("xcdevice list failed with exit code \(result.exitCode): \(result.stderr)")
                return []
            }
        } catch {
            Self.logger.error("Failed to run xcdevice: \(error.localizedDescription)")
            return []
        }
    }
}
