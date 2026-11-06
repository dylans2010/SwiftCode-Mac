import Foundation

/// The DeviceConnectKit commands, ported from Legacy
/// (`SwiftCode/Views/Build/DeviceConnectKit/Commands/`): one small
/// struct per developer-tool invocation (`xcodebuild`, `xcrun
/// xcdevice` / `devicectl` / `simctl`, `xcode-select`, `security`,
/// `sw_vers`, `swift`). Each runs a real tool through
/// `DeviceConnectProcessRunner` and reports the real result.
///
/// One deviation from Legacy: `BuildProjectCommand` no longer reads
/// `ProjectSessionStore.shared.activeProject` for a saved SDK — that
/// Legacy app type is not in this slice, and SDK selection belongs
/// to Ycode's build system (`YcodeXcodebuild`). The `-sdk` override
/// is dropped; the build uses the project's own settings.
public struct BuildProjectCommand {
    public init() {}

    public func execute(
        projectPath: String,
        scheme: String,
        configuration: String = "Debug",
        destination: String,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws -> Bool {
        let xcodebuildURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

        let derivedData = URL(fileURLWithPath: projectPath).deletingLastPathComponent().appendingPathComponent("build/DerivedData").path
        var args = [
            "-project", projectPath,
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination,
            "-derivedDataPath", derivedData,
            "build"
        ]

        if destination.lowercased().contains("simulator") || destination.hasPrefix("id=") {
            args.append(contentsOf: [
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO"
            ])
        }

        do {
            let success = try await DeviceConnectProcessRunner.shared.runStreamingAsync(
                executableURL: xcodebuildURL,
                arguments: args,
                onStdout: { line in
                    onLog(line)
                },
                onStderr: { errorLine in
                    onLog("[stderr] " + errorLine)
                }
            )
            return success
        } catch {
            onLog("Error starting build: \(error.localizedDescription)")
            return false
        }
    }
}

public struct DerivedDataCommand {
    public init() {}

    public func getDerivedDataSize() async throws -> Double {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let derivedDataURL = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")

        var totalSize: Double = 0
        if let enumerator = FileManager.default.enumerator(at: derivedDataURL, includingPropertiesForKeys: [.fileSizeKey]) {
            while let url = enumerator.nextObject() as? URL {
                if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let size = resourceValues.fileSize {
                    totalSize += Double(size)
                }
            }
        }
        return totalSize
    }

    public func clearDerivedData() async throws -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let derivedDataURL = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")

        do {
            if FileManager.default.fileExists(atPath: derivedDataURL.path) {
                try FileManager.default.removeItem(at: derivedDataURL)
                try FileManager.default.createDirectory(at: derivedDataURL, withIntermediateDirectories: true)
            }
            return true
        } catch {
            return false
        }
    }
}

public struct DeveloperDirectoryCommand {
    public init() {}

    public func execute() async throws -> String {
        let xcodeSelectURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        let res = try await DeviceConnectProcessRunner.shared.run(
            executableURL: xcodeSelectURL,
            arguments: ["-p"]
        )
        if res.exitCode == 0 {
            return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw NSError(domain: "com.swiftcode.deviceconnect", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: res.stderr])
        }
    }
}

public struct DeviceInfoCommand {
    public init() {}

    public func execute(deviceUDID: String) async throws -> [String: String] {
        let devicectlURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let args = [
            "devicectl", "device", "info", "details",
            "--device", deviceUDID
        ]

        do {
            let res = try await DeviceConnectProcessRunner.shared.run(
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

public struct DiagnosticsCommand {
    public init() {}

    public func execute() async throws -> String {
        let env = try await ValidateEnvironmentCommand().execute()
        let sdks = try await SDKValidationCommand().execute()
        let certs = try await SigningValidationCommand().execute()

        var report = "=== DeviceConnectKit System Diagnostics ===\n"
        report += "Date: \(Date())\n"
        report += "macOS Version: \(env.macOSVersion)\n"
        report += "Xcode Path: \(env.xcodePath ?? "Not Found")\n"
        report += "Xcode Version: \(env.xcodeVersion ?? "Not Found")\n"
        report += "Swift Version: \(env.swiftVersion ?? "Not Found")\n"
        report += "iOS SDK Available: \(env.hasiOSSDK ? "Yes" : "No")\n"
        report += "Simulator SDK Available: \(env.hasSimulatorSDK ? "Yes" : "No")\n"
        report += "Signing Configured: \(env.isSigningSetup ? "Yes" : "No")\n"

        report += "\n=== Available SDKs ===\n"
        if sdks.isEmpty {
            report += "No SDKs found.\n"
        } else {
            for sdk in sdks {
                report += "- \(sdk)\n"
            }
        }

        report += "\n=== Code Signing Identities ===\n"
        if certs.isEmpty {
            report += "No valid signing identities discovered.\n"
        } else {
            for cert in certs {
                report += "- \(cert)\n"
            }
        }

        return report
    }
}

public struct DiscoverDevicesCommand {
    public init() {}

    public func execute() async throws -> [ConnectedDevice] {
        let executable = URL(fileURLWithPath: "/usr/bin/xcrun")
        let args = ["xcdevice", "list"]

        do {
            let result = try await DeviceConnectProcessRunner.shared.run(
                executableURL: executable,
                arguments: args
            )

            if result.exitCode == 0 {
                return DeviceParser.parseXCDeviceList(result.stdout)
            } else {
                return []
            }
        } catch {
            return []
        }
    }
}

public struct InstallApplicationCommand {
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
            onProgress("Target is a simulator. Booting if necessary...")
            _ = try? await DeviceConnectProcessRunner.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "boot", deviceUDID]
            )

            onProgress("Running xcrun simctl install \(deviceUDID)...")
            let simSuccess = try await DeviceConnectProcessRunner.shared.runStreamingAsync(
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

        final class ErrorFlag: @unchecked Sendable {
            var hadCoreDeviceError = false
        }
        let errorFlag = ErrorFlag()

        do {
            let success = try await DeviceConnectProcessRunner.shared.runStreamingAsync(
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
                _ = try? await DeviceConnectProcessRunner.shared.run(
                    executableURL: xcrunURL,
                    arguments: ["simctl", "boot", deviceUDID]
                )
                let fallbackSuccess = try await DeviceConnectProcessRunner.shared.runStreamingAsync(
                    executableURL: xcrunURL,
                    arguments: ["simctl", "install", deviceUDID, appBundleURL.path],
                    onStdout: { line in onProgress(line) },
                    onStderr: { line in onProgress("[Error] " + line) }
                )
                return fallbackSuccess
            }

            return false
        } catch {
            // Secondary fallback attempt
            onProgress("[Recovery] Error running devicectl (\(error.localizedDescription)). Attempting simctl fallback...")
            let fallbackSuccess = try await DeviceConnectProcessRunner.shared.runStreamingAsync(
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
        if let result = try? await DeviceConnectProcessRunner.shared.run(
            executableURL: xcrunURL,
            arguments: ["simctl", "list", "devices", "-j"]
        ), result.exitCode == 0 {
            return result.stdout.contains(udid)
        }
        return false
    }
}

public struct LaunchApplicationCommand {
    public init() {}

    public func execute(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Int32? {
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        let isSim = await isSimulator(udid: deviceUDID)
        if isSim {
            // Ensure simulator booted
            _ = try? await DeviceConnectProcessRunner.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "boot", deviceUDID]
            )

            let simRes = try await DeviceConnectProcessRunner.shared.run(
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

        do {
            let res = try await DeviceConnectProcessRunner.shared.run(
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
                let simRes = try await DeviceConnectProcessRunner.shared.run(
                    executableURL: xcrunURL,
                    arguments: ["simctl", "launch", deviceUDID, bundleIdentifier]
                )
                if simRes.exitCode == 0 {
                    return 1
                }
                return nil
            }
        } catch {
            let simRes = try? await DeviceConnectProcessRunner.shared.run(
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
        if let result = try? await DeviceConnectProcessRunner.shared.run(
            executableURL: xcrunURL,
            arguments: ["simctl", "list", "devices", "-j"]
        ), result.exitCode == 0 {
            return result.stdout.contains(udid)
        }
        return false
    }
}

public struct RuntimeLogsCommand {
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

        return try DeviceConnectProcessRunner.shared.runStreaming(
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

public struct SDKValidationCommand {
    public init() {}

    public func execute() async throws -> [String] {
        let xcodebuildURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        let res = try await DeviceConnectProcessRunner.shared.run(
            executableURL: xcodebuildURL,
            arguments: ["-showsdks"]
        )

        if res.exitCode == 0 {
            return res.stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("-") || $0.contains("SDK") }
        } else {
            return []
        }
    }
}

public struct SigningValidationCommand {
    public init() {}

    public func execute() async throws -> [String] {
        let securityURL = URL(fileURLWithPath: "/usr/bin/security")
        let res = try await DeviceConnectProcessRunner.shared.run(
            executableURL: securityURL,
            arguments: ["find-identity", "-v", "-p", "codesigning"]
        )

        if res.exitCode == 0 {
            return res.stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.contains("\"") }
        } else {
            return []
        }
    }
}

public struct StopApplicationCommand {
    public init() {}

    public func execute(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Bool {
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        let isSim = await isSimulator(udid: deviceUDID)
        if isSim {
            let res = try? await DeviceConnectProcessRunner.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "terminate", deviceUDID, bundleIdentifier]
            )
            return res?.exitCode == 0
        }

        let args = [
            "devicectl", "device", "terminate", "app",
            "--device", deviceUDID,
            bundleIdentifier
        ]

        do {
            let res = try await DeviceConnectProcessRunner.shared.run(
                executableURL: xcrunURL,
                arguments: args
            )
            if res.exitCode == 0 {
                return true
            }
            // Fallback attempt
            let simRes = try? await DeviceConnectProcessRunner.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "terminate", deviceUDID, bundleIdentifier]
            )
            return simRes?.exitCode == 0
        } catch {
            let simRes = try? await DeviceConnectProcessRunner.shared.run(
                executableURL: xcrunURL,
                arguments: ["simctl", "terminate", deviceUDID, bundleIdentifier]
            )
            return simRes?.exitCode == 0
        }
    }

    private func isSimulator(udid: String) async -> Bool {
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        if let result = try? await DeviceConnectProcessRunner.shared.run(
            executableURL: xcrunURL,
            arguments: ["simctl", "list", "devices", "-j"]
        ), result.exitCode == 0 {
            return result.stdout.contains(udid)
        }
        return false
    }
}

public struct ValidateEnvironmentCommand {
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
            let res = try await DeviceConnectProcessRunner.shared.run(executableURL: URL(fileURLWithPath: "/usr/bin/sw_vers"), arguments: ["-productVersion"])
            macOSVersion = res.exitCode == 0 ? res.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : "macOS Unknown"
        } catch {
            macOSVersion = "macOS Unknown"
        }

        // 2. Xcode Select path
        do {
            let res = try await DeviceConnectProcessRunner.shared.run(executableURL: xcodeSelectURL, arguments: ["-p"])
            if res.exitCode == 0 {
                xcodePath = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // xcode-select not available; xcodePath stays nil.
        }

        // 3. Xcode Version
        do {
            let res = try await DeviceConnectProcessRunner.shared.run(executableURL: xcodebuildURL, arguments: ["-version"])
            if res.exitCode == 0 {
                xcodeVersion = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            }
        } catch {
            // xcodebuild not available; xcodeVersion stays nil.
        }

        // 4. Swift version
        do {
            let res = try await DeviceConnectProcessRunner.shared.run(executableURL: URL(fileURLWithPath: "/usr/bin/swift"), arguments: ["--version"])
            if res.exitCode == 0 {
                swiftVersion = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first
            }
        } catch {
            // swift not available; swiftVersion stays nil.
        }

        // 5. Check SDKs
        do {
            let res = try await DeviceConnectProcessRunner.shared.run(executableURL: xcodebuildURL, arguments: ["-showsdks"])
            if res.exitCode == 0 {
                let out = res.stdout.lowercased()
                hasiOSSDK = out.contains("iphoneos")
                hasSimulatorSDK = out.contains("iphonesimulator")
            }
        } catch {
            // Could not fetch SDK list.
        }

        // 6. Signing check (security find-identity)
        do {
            let res = try await DeviceConnectProcessRunner.shared.run(executableURL: URL(fileURLWithPath: "/usr/bin/security"), arguments: ["find-identity", "-v", "-p", "codesigning"])
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
