import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Build", category: "BuildDestinationResolver")

public struct ResolvedDestination: Sendable, Codable, Hashable, Identifiable {
    public var id: String {
        var parts: [String] = []
        if !platform.isEmpty { parts.append("platform=\(platform)") }
        if !name.isEmpty { parts.append("name=\(name)") }
        if !os.isEmpty { parts.append("OS=\(os)") }
        if !idString.isEmpty { parts.append("id=\(idString)") }
        if !variant.isEmpty { parts.append("variant=\(variant)") }
        if !arch.isEmpty { parts.append("arch=\(arch)") }
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
            if let targetPlatform = project.ciBuildConfiguration?.targetPlatform {
                if targetPlatform.lowercased().contains("ios") {
                    supportedPlatforms = ["iphonesimulator", "iphoneos"]
                    baseSDK = "iphonesimulator"
                    deploymentTarget = "16.0"
                }
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

        if destinations.isEmpty {
            destinations = fallbackDestinations(for: settings.supportedPlatforms)
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

    private func fallbackDestinations(for supportedPlatforms: [String]) -> [ResolvedDestination] {
        var list: [ResolvedDestination] = []
        for platform in supportedPlatforms {
            let lower = platform.lowercased()
            if lower.contains("macosx") || lower.contains("macos") {
                list.append(ResolvedDestination(platform: "macOS", name: "My Mac", os: "", idString: "", variant: "", arch: "arm64"))
            } else if lower.contains("iphonesimulator") || lower.contains("ios") {
                list.append(ResolvedDestination(platform: "iOS Simulator", name: "iPhone 15", os: "18.0", idString: "", variant: "", arch: ""))
            } else if lower.contains("iphoneos") {
                list.append(ResolvedDestination(platform: "iOS", name: "Any iOS Device", os: "", idString: "", variant: "", arch: ""))
            } else if lower.contains("watch") {
                list.append(ResolvedDestination(platform: "watchOS Simulator", name: "Apple Watch Series 9", os: "11.0", idString: "", variant: "", arch: ""))
            } else if lower.contains("tv") {
                list.append(ResolvedDestination(platform: "tvOS Simulator", name: "Apple TV", os: "18.0", idString: "", variant: "", arch: ""))
            } else if lower.contains("xr") || lower.contains("vision") {
                list.append(ResolvedDestination(platform: "visionOS Simulator", name: "Apple Vision Pro", os: "2.0", idString: "", variant: "", arch: ""))
            }
        }
        if list.isEmpty {
            list.append(ResolvedDestination(platform: "macOS", name: "My Mac", os: "", idString: "", variant: "", arch: ""))
        }
        return list
    }

    /// Selects the best compatible destination and SDK automatically
    public func selectBestDestination(settings: ResolvedSettings, destinations: [ResolvedDestination]) -> (sdk: String, destination: ResolvedDestination)? {
        let isMacOS = settings.supportedPlatforms.contains { $0.lowercased().contains("macosx") || $0.lowercased() == "macos" }
        let isiOS = settings.supportedPlatforms.contains { $0.lowercased().contains("iphone") || $0.lowercased().contains("ios") }
        let isVisionOS = settings.supportedPlatforms.contains { $0.lowercased().contains("vision") || $0.lowercased().contains("xr") }
        let isWatchOS = settings.supportedPlatforms.contains { $0.lowercased().contains("watch") }
        let isTvOS = settings.supportedPlatforms.contains { $0.lowercased().contains("appletv") || $0.lowercased().contains("tvos") }

        if isMacOS {
            if let dest = destinations.first(where: { $0.platform.lowercased() == "macos" }) {
                return ("macosx", dest)
            }
        }

        if isiOS {
            if let dest = destinations.first(where: { $0.platform.lowercased() == "ios simulator" }) {
                return ("iphonesimulator", dest)
            }
            if let dest = destinations.first(where: { $0.platform.lowercased() == "ios" }) {
                return ("iphoneos", dest)
            }
        }

        if isVisionOS {
            if let dest = destinations.first(where: { $0.platform.lowercased().contains("vision") && $0.platform.lowercased().contains("simulator") }) {
                return ("xrsimulator", dest)
            }
        }

        if isWatchOS {
            if let dest = destinations.first(where: { $0.platform.lowercased().contains("watch") && $0.platform.lowercased().contains("simulator") }) {
                return ("watchsimulator", dest)
            }
        }

        if isTvOS {
            if let dest = destinations.first(where: { $0.platform.lowercased().contains("tv") && $0.platform.lowercased().contains("simulator") }) {
                return ("appletvsimulator", dest)
            }
        }

        if let first = destinations.first {
            let sdk = first.platform.lowercased().contains("macos") ? "macosx" : "iphonesimulator"
            return (sdk, first)
        }

        return nil
    }
}
