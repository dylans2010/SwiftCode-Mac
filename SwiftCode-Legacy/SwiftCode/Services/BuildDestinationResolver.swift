import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Build", category: "BuildDestinationResolver")

public struct ResolvedDestination: Sendable, Codable, Hashable, Identifiable {
    public var id: String {
        if !idString.isEmpty && !idString.contains("placeholder") {
            if !platform.isEmpty {
                return "platform=\(platform),id=\(idString)"
            }
            return "id=\(idString)"
        }
        var parts: [String] = []
        if !platform.isEmpty { parts.append("platform=\(platform)") }
        if !name.isEmpty && !name.contains("Any ") { parts.append("name=\(name)") }
        if !os.isEmpty { parts.append("OS=\(os)") }
        if !variant.isEmpty { parts.append("variant=\(variant)") }
        if !arch.isEmpty { parts.append("arch=\(arch)") }
        if parts.isEmpty { return "generic/platform=\(platform.isEmpty ? "iOS" : platform)" }
        return parts.joined(separator: ",")
    }
    public let platform: String
    public let name: String
    public let os: String
    public let idString: String
    public let variant: String
    public let arch: String

    public init(platform: String, name: String, os: String, idString: String, variant: String, arch: String) {
        self.platform = platform
        self.name = name
        self.os = os
        self.idString = idString
        self.variant = variant
        self.arch = arch
    }
}

@MainActor
public final class BuildDestinationResolver {
    public static let shared = BuildDestinationResolver()
    public private(set) var cachedSimulators: [ResolvedDestination] = []

    private init() {}

    public struct ResolvedSettings {
        public let supportedPlatforms: [String]
        public let baseSDK: String
        public let deploymentTarget: String
        public let scheme: String
        public let workspaceOrProject: URL
    }

    /// Queries xcodebuild -showBuildSettings to resolve platform details
    public func resolveSettings(for projectURL: URL, scheme: String) async throws -> ResolvedSettings {
        let xcodebuildPath = XcodeBuildManager.shared.getXcodeBuildPath()
        let projectArgKey = projectURL.pathExtension == "xcworkspace" ? "-workspace" : "-project"

        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: xcodebuildPath),
                arguments: [
                    projectArgKey, projectURL.path,
                    "-scheme", scheme,
                    "-showBuildSettings"
                ],
                workingDirectory: projectURL.deletingLastPathComponent()
            )

            if result.exitCode == 0 {
                return parseBuildSettings(result.stdout, projectURL: projectURL, scheme: scheme)
            }
        } catch {
            logger.warning("Failed to run showBuildSettings: \(error.localizedDescription)")
        }

        // Fallback if xcodebuild fails or lacks Xcode
        return try resolveSettingsFallback(for: projectURL, scheme: scheme)
    }

    private func parseBuildSettings(_ output: String, projectURL: URL, scheme: String) -> ResolvedSettings {
        var supportedPlatforms: [String] = []
        var baseSDK = ""
        var deploymentTarget = ""

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("SUPPORTED_PLATFORMS =") {
                let val = trimmed.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                supportedPlatforms = val.components(separatedBy: .whitespaces).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } else if trimmed.hasPrefix("SDK_NAME =") {
                baseSDK = trimmed.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } else if trimmed.hasPrefix("IPHONEOS_DEPLOYMENT_TARGET =") {
                deploymentTarget = trimmed.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } else if trimmed.hasPrefix("MACOSX_DEPLOYMENT_TARGET =") {
                deploymentTarget = trimmed.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        }

        if supportedPlatforms.isEmpty {
            if baseSDK.lowercased().contains("macosx") {
                supportedPlatforms = ["macosx"]
            } else if baseSDK.lowercased().contains("iphone") {
                supportedPlatforms = ["iphonesimulator", "iphoneos"]
            } else {
                supportedPlatforms = ["macosx"]
            }
        }

        return ResolvedSettings(
            supportedPlatforms: supportedPlatforms,
            baseSDK: baseSDK,
            deploymentTarget: deploymentTarget,
            scheme: scheme,
            workspaceOrProject: projectURL
        )
    }

    private func resolveSettingsFallback(for projectURL: URL, scheme: String) throws -> ResolvedSettings {
        var supportedPlatforms = ["macosx"]
        var baseSDK = "macosx"
        var deploymentTarget = "15.0"

        if let project = ProjectSessionStore.shared.activeProject {
            if let targetPlatform = project.ciBuildConfiguration?.platform.rawValue {
                if targetPlatform.lowercased().contains("ios") {
                    supportedPlatforms = ["iphonesimulator", "iphoneos"]
                    baseSDK = "iphonesimulator"
                    deploymentTarget = "16.0"
                }
            }
        }

        // Direct inspection of project.pbxproj if available
        let pbxprojURL = projectURL.pathExtension == "xcodeproj" ? projectURL.appendingPathComponent("project.pbxproj") : projectURL.appendingPathComponent("\(scheme).xcodeproj/project.pbxproj")
        if let pbxContent = try? String(contentsOf: pbxprojURL, encoding: .utf8) {
            let lower = pbxContent.lowercased()
            if lower.contains("iphoneos") || lower.contains("iphonesimulator") {
                supportedPlatforms = ["iphonesimulator", "iphoneos"]
                baseSDK = "iphonesimulator"
                deploymentTarget = "17.0"
            }
        }

        return ResolvedSettings(
            supportedPlatforms: supportedPlatforms,
            baseSDK: baseSDK,
            deploymentTarget: deploymentTarget,
            scheme: scheme,
            workspaceOrProject: projectURL
        )
    }

    /// Queries xcodebuild -showdestinations and filters them based on active platforms
    public func resolveDestinations(for projectURL: URL, scheme: String, settings: ResolvedSettings) async -> [ResolvedDestination] {
        let xcodebuildPath = XcodeBuildManager.shared.getXcodeBuildPath()
        let projectArgKey = projectURL.pathExtension == "xcworkspace" ? "-workspace" : "-project"

        var destinations: [ResolvedDestination] = []

        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: xcodebuildPath),
                arguments: [
                    projectArgKey, projectURL.path,
                    "-scheme", scheme,
                    "-showdestinations"
                ],
                workingDirectory: projectURL.deletingLastPathComponent()
            )

            if result.exitCode == 0 {
                destinations = parseDestinations(result.stdout)
            }
        } catch {
            logger.warning("Failed to run showdestinations: \(error.localizedDescription)")
        }

        // Filter out unusable placeholder destinations
        destinations = destinations.filter { !$0.idString.contains("placeholder") }

        if destinations.isEmpty {
            destinations = await fallbackDestinations(for: settings.supportedPlatforms)
        }

        return destinations
    }

    public func parseDestinations(_ output: String) -> [ResolvedDestination] {
        var results: [ResolvedDestination] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else { continue }

            let content = String(trimmed.dropFirst().dropLast())
            var dict: [String: String] = [:]

            let pairs = content.components(separatedBy: ",")
            for pair in pairs {
                let parts = pair.components(separatedBy: ":")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let val = parts.suffix(from: 1).joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                    dict[key] = val
                }
            }

            if let platform = dict["platform"] {
                results.append(ResolvedDestination(
                    platform: platform,
                    name: dict["name"] ?? "",
                    os: dict["OS"] ?? dict["os"] ?? "",
                    idString: dict["id"] ?? "",
                    variant: dict["variant"] ?? "",
                    arch: dict["arch"] ?? ""
                ))
            }
        }
        return results
    }

    /// Dynamically fetches available simulator devices via simctl CLI process
    public func fetchAvailableSimulators() async -> [ResolvedDestination] {
        do {
            let result = try await ProcessRunnerTool.shared.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "list", "devices", "available", "-j"]
            )
            guard result.exitCode == 0, let data = result.stdout.data(using: .utf8) else {
                return []
            }

            struct SimctlResponse: Decodable {
                let devices: [String: [SimctlDeviceItem]]
            }
            struct SimctlDeviceItem: Decodable {
                let name: String
                let udid: String
                let state: String
                let isAvailable: Bool?
            }

            let decoded = try JSONDecoder().decode(SimctlResponse.self, from: data)
            var sims: [ResolvedDestination] = []

            for (runtimeKey, deviceList) in decoded.devices {
                let platform: String
                let lowerRuntime = runtimeKey.lowercased()
                if lowerRuntime.contains("ios") {
                    platform = "iOS Simulator"
                } else if lowerRuntime.contains("watch") {
                    platform = "watchOS Simulator"
                } else if lowerRuntime.contains("tv") {
                    platform = "tvOS Simulator"
                } else if lowerRuntime.contains("xr") || lowerRuntime.contains("vision") {
                    platform = "visionOS Simulator"
                } else {
                    platform = "iOS Simulator"
                }

                for dev in deviceList where dev.isAvailable ?? true {
                    let dest = ResolvedDestination(
                        platform: platform,
                        name: dev.name,
                        os: "",
                        idString: dev.udid,
                        variant: dev.state == "Booted" ? "Booted" : "",
                        arch: "arm64"
                    )
                    if dev.state == "Booted" {
                        sims.insert(dest, at: 0)
                    } else {
                        sims.append(dest)
                    }
                }
            }
            self.cachedSimulators = sims
            return sims
        } catch {
            logger.warning("Failed to fetch available simulators via simctl: \(error.localizedDescription)")
            return []
        }
    }

    private func fallbackDestinations(for supportedPlatforms: [String]) async -> [ResolvedDestination] {
        let liveSims = await fetchAvailableSimulators()
        var list: [ResolvedDestination] = []

        for platform in supportedPlatforms {
            let lower = platform.lowercased()
            if lower.contains("macosx") || lower.contains("macos") {
                list.append(ResolvedDestination(platform: "macOS", name: "My Mac", os: "", idString: "", variant: "", arch: "arm64"))
            } else if lower.contains("iphonesimulator") || lower.contains("ios") {
                let iosSims = liveSims.filter { $0.platform == "iOS Simulator" }
                if !iosSims.isEmpty {
                    list.append(contentsOf: iosSims)
                } else {
                    list.append(ResolvedDestination(platform: "iOS Simulator", name: "Any iOS Simulator Device", os: "", idString: "", variant: "", arch: ""))
                }
            } else if lower.contains("iphoneos") {
                list.append(ResolvedDestination(platform: "iOS", name: "Any iOS Device", os: "", idString: "", variant: "", arch: ""))
            } else if lower.contains("watch") {
                let watchSims = liveSims.filter { $0.platform == "watchOS Simulator" }
                if !watchSims.isEmpty {
                    list.append(contentsOf: watchSims)
                }
            } else if lower.contains("tv") {
                let tvSims = liveSims.filter { $0.platform == "tvOS Simulator" }
                if !tvSims.isEmpty {
                    list.append(contentsOf: tvSims)
                }
            } else if lower.contains("xr") || lower.contains("vision") {
                let visionSims = liveSims.filter { $0.platform == "visionOS Simulator" }
                if !visionSims.isEmpty {
                    list.append(contentsOf: visionSims)
                }
            }
        }

        if list.isEmpty {
            if !liveSims.isEmpty {
                list.append(contentsOf: liveSims)
            } else {
                list.append(ResolvedDestination(platform: "macOS", name: "My Mac", os: "", idString: "", variant: "", arch: "arm64"))
            }
        }
        return list
    }

    /// Selects the best compatible destination and SDK automatically
    public func selectBestDestination(settings: ResolvedSettings, destinations: [ResolvedDestination]) -> (sdk: String, destination: ResolvedDestination)? {
        let validDestinations = destinations.filter { !$0.idString.contains("placeholder") }

        let isiOS = settings.supportedPlatforms.contains { $0.lowercased().contains("iphone") || $0.lowercased().contains("ios") }
        let isMacOS = settings.supportedPlatforms.contains { $0.lowercased().contains("macosx") || $0.lowercased() == "macos" }
        let isVisionOS = settings.supportedPlatforms.contains { $0.lowercased().contains("vision") || $0.lowercased().contains("xr") }
        let isWatchOS = settings.supportedPlatforms.contains { $0.lowercased().contains("watch") }
        let isTvOS = settings.supportedPlatforms.contains { $0.lowercased().contains("appletv") || $0.lowercased().contains("tvos") }

        // iOS priority if configured
        if isiOS {
            if let booted = validDestinations.first(where: { $0.platform.lowercased() == "ios simulator" && $0.variant == "Booted" && !$0.idString.isEmpty }) {
                return ("iphonesimulator", booted)
            }
            if let concrete = validDestinations.first(where: { $0.platform.lowercased() == "ios simulator" && !$0.idString.isEmpty }) {
                return ("iphonesimulator", concrete)
            }
            if let dest = validDestinations.first(where: { $0.platform.lowercased() == "ios simulator" }) {
                return ("iphonesimulator", dest)
            }
            if let dest = validDestinations.first(where: { $0.platform.lowercased() == "ios" }) {
                return ("iphoneos", dest)
            }
        }

        if isMacOS && !isiOS {
            if let dest = validDestinations.first(where: { $0.platform.lowercased() == "macos" }) {
                return ("macosx", dest)
            }
        }

        if isVisionOS {
            if let dest = validDestinations.first(where: { $0.platform.lowercased().contains("vision") && $0.platform.lowercased().contains("simulator") }) {
                return ("xrsimulator", dest)
            }
        }

        if isWatchOS {
            if let dest = validDestinations.first(where: { $0.platform.lowercased().contains("watch") && $0.platform.lowercased().contains("simulator") }) {
                return ("watchsimulator", dest)
            }
        }

        if isTvOS {
            if let dest = validDestinations.first(where: { $0.platform.lowercased().contains("tv") && $0.platform.lowercased().contains("simulator") }) {
                return ("appletvsimulator", dest)
            }
        }

        if isMacOS {
            if let dest = validDestinations.first(where: { $0.platform.lowercased() == "macos" }) {
                return ("macosx", dest)
            }
        }

        if let first = validDestinations.first {
            let sdk = first.platform.lowercased().contains("macos") ? "macosx" : "iphonesimulator"
            return (sdk, first)
        }

        return nil
    }
}
