import Foundation
import OSLog

public struct ValidateEnvironmentCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "ValidateEnvironmentCommand")

    public init() {}

    public func execute() async throws -> DeviceEnvironment {
        let xcodeSelectURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        let xcodebuildURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

        var xcodePath: String? = nil
        var xcodeVersion: String? = nil
        var clToolsVersion: String? = nil
        let macOSVersion: String
        var hasiOSSDK = false
        var hasSimulatorSDK = false
        var isSigningSetup = false
        var derivedData: String? = nil
        var swiftVersion: String? = nil

        // 1. macOS version
        do {
            let res = try await ProcessRunnerTool.shared.run(executableURL: URL(fileURLWithPath: "/usr/bin/sw_vers"), arguments: ["-productVersion"])
            macOSVersion = res.exitCode == 0 ? res.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : "macOS Unknown"
        } catch {
            macOSVersion = "macOS Unknown"
        }

        // 2. Xcode Select path
        do {
            let res = try await ProcessRunnerTool.shared.run(executableURL: xcodeSelectURL, arguments: ["-p"])
            if res.exitCode == 0 {
                xcodePath = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            Self.logger.warning("xcode-select not available.")
        }

        // 3. Xcode Version
        do {
            let res = try await ProcessRunnerTool.shared.run(executableURL: xcodebuildURL, arguments: ["-version"])
            if res.exitCode == 0 {
                xcodeVersion = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            }
        } catch {
            Self.logger.warning("xcodebuild not available.")
        }

        // 4. Swift version
        do {
            let res = try await ProcessRunnerTool.shared.run(executableURL: URL(fileURLWithPath: "/usr/bin/swift"), arguments: ["--version"])
            if res.exitCode == 0 {
                swiftVersion = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first
            }
        } catch {
            Self.logger.warning("swift not available.")
        }

        // 5. Check SDKs
        do {
            let res = try await ProcessRunnerTool.shared.run(executableURL: xcodebuildURL, arguments: ["-showsdks"])
            if res.exitCode == 0 {
                let out = res.stdout.lowercased()
                hasiOSSDK = out.contains("iphoneos")
                hasSimulatorSDK = out.contains("iphonesimulator")
            }
        } catch {
            Self.logger.warning("Could not fetch SDK list.")
        }

        // 6. Signing check (security find-identity)
        do {
            let res = try await ProcessRunnerTool.shared.run(executableURL: URL(fileURLWithPath: "/usr/bin/security"), arguments: ["find-identity", "-v", "-p", "codesigning"])
            isSigningSetup = res.exitCode == 0 && res.stdout.contains("matching identities")
        } catch {
            isSigningSetup = false
        }

        return DeviceEnvironment(
            xcodePath: xcodePath,
            xcodeVersion: xcodeVersion,
            commandLineToolsVersion: clToolsVersion,
            macOSVersion: macOSVersion,
            hasiOSSDK: hasiOSSDK,
            hasSimulatorSDK: hasSimulatorSDK,
            isSigningSetup: isSigningSetup,
            derivedDataPath: derivedData,
            swiftVersion: swiftVersion
        )
    }
}
