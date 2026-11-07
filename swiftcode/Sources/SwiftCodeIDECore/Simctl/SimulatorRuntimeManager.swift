import Foundation
import Observation
import os

@Observable
@MainActor
public final class SimulatorRuntimeManager {
    public static let shared = SimulatorRuntimeManager()

    private var cachedRuntimes: [String: [SimulatorRuntime]] = [:]

    private let logger = Logger.discovery

    private init() {}

    public func discoverRuntimes() async -> [SimulatorRuntime] {
        logger.info("[RUNTIME-MANAGER] Discovering runtimes from default paths...")

        let defaultPaths = [
            "/Library/Developer/CoreSimulator/Profiles/Runtimes/",
            getHomeRuntimesPath()
        ]

        var allRuntimes: [SimulatorRuntime] = []
        for path in defaultPaths {
            guard !path.isEmpty else { continue }
            let runtimes = await getRuntimesFromCustomPath(path)
            allRuntimes.append(contentsOf: runtimes)
        }

        var uniqueRuntimes: [SimulatorRuntime] = []
        var seenIDs = Set<String>()
        for runtime in allRuntimes {
            if !seenIDs.contains(runtime.identifier) {
                seenIDs.insert(runtime.identifier)
                uniqueRuntimes.append(runtime)
            }
        }

        return uniqueRuntimes
    }

    public func getRuntimesFromCustomPath(_ path: String) async -> [SimulatorRuntime] {
        let expandedPath = (path as NSString).expandingTildeInPath

        if let cached = cachedRuntimes[expandedPath] {
            logger.info("[RUNTIME-MANAGER] Returning cached runtimes for path: \(expandedPath)")
            return cached
        }

        logger.info("[RUNTIME-MANAGER] Scanning path: \(expandedPath)")

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue else {
            logger.warning("[RUNTIME-MANAGER] Directory does not exist or is not a directory: \(expandedPath)")
            return []
        }

        var runtimes: [SimulatorRuntime] = []

        do {
            let contents = try fm.contentsOfDirectory(atPath: expandedPath)
            let simruntimeFolders = contents.filter { $0.hasSuffix(".simruntime") }

            for folderName in simruntimeFolders {
                let fullFolderURL = URL(fileURLWithPath: expandedPath).appendingPathComponent(folderName)
                if let runtime = parseSimruntimeBundle(at: fullFolderURL) {
                    runtimes.append(runtime)
                }
            }

            cachedRuntimes[expandedPath] = runtimes

        } catch {
            logger.error("[RUNTIME-MANAGER] Failed to read directory \(expandedPath): \(error.localizedDescription)")
        }

        return runtimes
    }

    public func clearCache() {
        cachedRuntimes.removeAll()
    }

    private func getHomeRuntimesPath() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent("Library/Developer/CoreSimulator/Profiles/Runtimes/").path
    }

    private func parseSimruntimeBundle(at url: URL) -> SimulatorRuntime? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        let fm = FileManager.default

        guard fm.fileExists(atPath: plistURL.path) else {
            logger.warning("[RUNTIME-MANAGER] Missing Info.plist at: \(plistURL.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: plistURL)
            guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                logger.warning("[RUNTIME-MANAGER] Info.plist at \(plistURL.path) is not a dictionary.")
                return nil
            }

            let bundleName = plist["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
            let version = plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String ?? "Unknown"
            let identifier = plist["CFBundleIdentifier"] as? String ?? "com.apple.CoreSimulator.SimRuntime.custom-\(UUID().uuidString)"

            let platform: String = {
                if let simPlatform = plist["SimulatorPlatform"] as? String {
                    return simPlatform
                }
                let lowerName = bundleName.lowercased()
                let lowerID = identifier.lowercased()

                if lowerName.contains("ios") || lowerID.contains("ios") {
                    return "iOS"
                } else if lowerName.contains("watch") || lowerID.contains("watch") {
                    return "watchOS"
                } else if lowerName.contains("tv") || lowerID.contains("tv") {
                    return "tvOS"
                } else if lowerName.contains("vision") || lowerID.contains("vision") {
                    return "visionOS"
                } else if lowerName.contains("macos") || lowerID.contains("macos") {
                    return "macOS"
                }
                return "iOS"
            }()

            return SimulatorRuntime(
                identifier: identifier,
                name: bundleName,
                version: version,
                platform: platform,
                isAvailable: true,
                path: url.path
            )

        } catch {
            logger.error("[RUNTIME-MANAGER] Failed to parse Info.plist at \(plistURL.path): \(error.localizedDescription)")
            return nil
        }
    }
}
