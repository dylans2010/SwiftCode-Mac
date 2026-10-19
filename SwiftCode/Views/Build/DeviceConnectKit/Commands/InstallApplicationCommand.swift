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
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        // Check if device is a simulator
        let isSim = await isSimulator(udid: deviceUDID)

        if isSim {
            Self.logger.info("Installing to simulator \(deviceUDID) via simctl...")
            onProgress("Target is a simulator. Booting if necessary...")
            _ = try? await ProcessRunnerTool.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "boot", deviceUDID]
            )

            onProgress("Running xcrun simctl install \(deviceUDID)...")
            let simSuccess = try await ProcessRunnerTool.shared.runStreamingAsync(
                executableURL: xcrunURL,
                arguments: ["simctl", "install", deviceUDID, appBundleURL.path],
                onStdout: { line in onProgress(line) },
                onStderr: { line in onProgress("[Error] " + line) }
            )
            return simSuccess
        }

        // Physical device installation via devicectl
        let args = [
            "devicectl", "device", "install", "app",
            "--device", deviceUDID,
            appBundleURL.path
        ]

        Self.logger.info("Installing app to physical device \(deviceUDID) via devicectl...")
        final class ErrorFlag: @unchecked Sendable {
            var hadCoreDeviceError = false
        }
        let errorFlag = ErrorFlag()

        do {
            let success = try await ProcessRunnerTool.shared.runStreamingAsync(
                executableURL: xcrunURL,
                arguments: args,
                onStdout: { line in
                    onProgress(line)
                },
                onStderr: { line in
                    if line.contains("CoreDeviceError error 1001") || line.contains("not supported by this device") {
                        errorFlag.hadCoreDeviceError = true
                    }
                    onProgress("[Error] " + line)
                }
            )

            if success {
                return true
            }

            // Fallback to simctl if devicectl failed due to simulator / non-CoreDevice device
            if errorFlag.hadCoreDeviceError {
                onProgress("[Recovery] Device does not support devicectl. Retrying via xcrun simctl...")
                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: xcrunURL,
                    arguments: ["simctl", "boot", deviceUDID]
                )
                let fallbackSuccess = try await ProcessRunnerTool.shared.runStreamingAsync(
                    executableURL: xcrunURL,
                    arguments: ["simctl", "install", deviceUDID, appBundleURL.path],
                    onStdout: { line in onProgress(line) },
                    onStderr: { line in onProgress("[Error] " + line) }
                )
                return fallbackSuccess
            }

            return false
        } catch {
            Self.logger.error("Failed to run devicectl install: \(error.localizedDescription)")
            // Secondary fallback attempt
            onProgress("[Recovery] Error running devicectl (\(error.localizedDescription)). Attempting simctl fallback...")
            let fallbackSuccess = try await ProcessRunnerTool.shared.runStreamingAsync(
                executableURL: xcrunURL,
                arguments: ["simctl", "install", deviceUDID, appBundleURL.path],
                onStdout: { line in onProgress(line) },
                onStderr: { line in onProgress("[Error] " + line) }
            )
            return fallbackSuccess
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
