import Foundation
import OSLog

public struct DeviceInfoCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "DeviceInfoCommand")

    public init() {}

    public func execute(deviceUDID: String) async throws -> [String: String] {
        let devicectlURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let args = [
            "devicectl", "device", "info", "details",
            "--device", deviceUDID
        ]

        Self.logger.info("Fetching details for \(deviceUDID)...")

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: devicectlURL,
                arguments: args
            )

            if res.exitCode == 0 {
                var info: [String: String] = [:]
                let lines = res.stdout.components(separatedBy: .newlines)
                for line in lines {
                    let parts = line.components(separatedBy: ":")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        let val = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                        info[key] = val
                    }
                }
                return info
            } else {
                return ["Error": "Command failed with code \(res.exitCode)"]
            }
        } catch {
            return ["Error": error.localizedDescription]
        }
    }
}
