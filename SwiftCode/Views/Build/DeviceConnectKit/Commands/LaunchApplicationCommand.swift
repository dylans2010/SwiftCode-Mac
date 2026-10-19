import Foundation
import OSLog

public struct LaunchApplicationCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "LaunchApplicationCommand")

    public init() {}

    public func execute(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Int32? {
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        let isSim = await isSimulator(udid: deviceUDID)
        if isSim {
            Self.logger.info("Launching \(bundleIdentifier) on simulator \(deviceUDID) via simctl...")
            // Ensure simulator booted
            _ = try? await ProcessRunnerTool.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "boot", deviceUDID]
            )

            let simRes = try await ProcessRunnerTool.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "launch", deviceUDID, bundleIdentifier]
            )
            if simRes.exitCode == 0 {
                let trimmed = simRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if let pid = Int32(trimmed.components(separatedBy: ": ").last ?? "") {
                    return pid
                }
                return 1
            }
        }

        let args = [
            "devicectl", "device", "launch", "app",
            "--device", deviceUDID,
            bundleIdentifier
        ]

        Self.logger.info("Launching \(bundleIdentifier) on \(deviceUDID) via devicectl...")

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: xcrunURL,
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
                Self.logger.warning("devicectl launch returned non-zero. Attempting simctl launch fallback...")
                let simRes = try await ProcessRunnerTool.shared.run(
                    executableURL: xcrunURL,
                    arguments: ["simctl", "launch", deviceUDID, bundleIdentifier]
                )
                if simRes.exitCode == 0 {
                    return 1
                }
                Self.logger.error("Launch command failed: \(res.stderr)")
                return nil
            }
        } catch {
            Self.logger.error("Failed to execute launch via devicectl: \(error.localizedDescription). Falling back to simctl...")
            let simRes = try? await ProcessRunnerTool.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "launch", deviceUDID, bundleIdentifier]
            )
            if simRes?.exitCode == 0 {
                return 1
            }
            return nil
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
