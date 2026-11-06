import Foundation
import os

public struct DeveloperEnvironmentInfo: Sendable, Codable, Hashable {
    public let developerDirectory: String
    public let xcodeVersion: String?
    public let xcodeBuild: String?
    public let xcrunVersion: String?
    public let isFullXcodeInstall: Bool
    public let isCLTOnly: Bool

    public static let unavailable = DeveloperEnvironmentInfo(
        developerDirectory: "Unavailable",
        xcodeVersion: nil,
        xcodeBuild: nil,
        xcrunVersion: nil,
        isFullXcodeInstall: false,
        isCLTOnly: false
    )
}

public actor DeveloperEnvironmentProbe {
    public static let shared = DeveloperEnvironmentProbe()

    private init() {}

    public func runProbe() async -> DeveloperEnvironmentInfo {
        Logger.discovery.info("[PROBE] Running developer environment probes...")

        // 1. xcode-select -p
        let selectSpec = CommandSpec(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["-p"]
        )
        let selectRecord = await CommandExecutionEngine.shared.execute(selectSpec)

        guard selectRecord.exitCode == 0 else {
            Logger.discovery.error("[PROBE] xcode-select -p failed with code \(selectRecord.exitCode)")
            return .unavailable
        }

        let devDir = selectRecord.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCLTOnly = devDir.contains("CommandLineTools")

        // 2. xcodebuild -version
        var xcodeVersion: String?
        var xcodeBuild: String?
        if FileManager.default.fileExists(atPath: "/usr/bin/xcodebuild") {
            let buildSpec = CommandSpec(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: ["-version"]
            )
            let buildRecord = await CommandExecutionEngine.shared.execute(buildSpec)
            if buildRecord.exitCode == 0 {
                let lines = buildRecord.stdoutString.components(separatedBy: .newlines)
                for line in lines {
                    if line.starts(with: "Xcode ") {
                        xcodeVersion = line.replacingOccurrences(of: "Xcode ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if line.starts(with: "Build version ") {
                        xcodeBuild = line.replacingOccurrences(of: "Build version ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } else {
                Logger.discovery.warning("[PROBE] xcodebuild -version failed with code \(buildRecord.exitCode)")
            }
        }

        // 3. xcrun --version
        var xcrunVersion: String?
        if FileManager.default.fileExists(atPath: "/usr/bin/xcrun") {
            let xcrunSpec = CommandSpec(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["--version"]
            )
            let xcrunRecord = await CommandExecutionEngine.shared.execute(xcrunSpec)
            if xcrunRecord.exitCode == 0 {
                xcrunVersion = xcrunRecord.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                Logger.discovery.warning("[PROBE] xcrun --version failed with code \(xcrunRecord.exitCode)")
            }
        }

        let isFullXcodeInstall = !isCLTOnly && xcodeVersion != nil

        let info = DeveloperEnvironmentInfo(
            developerDirectory: devDir,
            xcodeVersion: xcodeVersion,
            xcodeBuild: xcodeBuild,
            xcrunVersion: xcrunVersion,
            isFullXcodeInstall: isFullXcodeInstall,
            isCLTOnly: isCLTOnly
        )

        Logger.discovery.info("[PROBE] Probe complete. Full Xcode: \(isFullXcodeInstall), CLT Only: \(isCLTOnly), Path: \(devDir)")
        return info
    }
}
