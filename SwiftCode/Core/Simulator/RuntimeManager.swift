import Foundation
import Observation
import os

/// A manager that handles runtime discovery for Simulator runtimes.
/// It scans default system/user directories and parses plist files to detect valid `.simruntime` bundles,
/// or scans user-defined custom directories. Discovered runtimes are cached to avoid redundant file scans.
@Observable
@MainActor
public final class RuntimeManager {
    public static let shared = RuntimeManager()

    // Cache of discovered runtimes by directory path to avoid repeating file system scans.
    private var cachedRuntimes: [String: [SimulatorRuntime]] = [:]

    // Logging category for runtime management.
    private let logger = Logger.discovery

    private init() {}

    /// Scans the default macOS simulator runtime directories.
    /// Default directories checked:
    /// - `/Library/Developer/CoreSimulator/Profiles/Runtimes/`
    /// - `~/Library/Developer/CoreSimulator/Profiles/Runtimes/`
    ///
    /// - Returns: An array of unique discovered `SimulatorRuntime` instances.
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

        // De-duplicate discovered runtimes based on their unique bundle identifier
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

    /// Scans a custom directory path for any valid `.simruntime` bundles.
    /// If the directory has been scanned previously, cached results are returned.
    ///
    /// - Parameter path: The directory path to scan.
    /// - Returns: An array of discovered `SimulatorRuntime` instances under that path.
    public func getRuntimesFromCustomPath(_ path: String) async -> [SimulatorRuntime] {
        let expandedPath = (path as NSString).expandingTildeInPath

        // Check cache first to avoid redundant disk I/O
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

            // Cache the scan results
            cachedRuntimes[expandedPath] = runtimes

        } catch {
            logger.error("[RUNTIME-MANAGER] Failed to read directory \(expandedPath): \(error.localizedDescription)")
        }

        return runtimes
    }

    /// Clears the cached discovered runtimes, forcing a full scan on subsequent operations.
    public func clearCache() {
        cachedRuntimes.removeAll()
    }

    // MARK: - Private Helpers

    /// Computes the correct home directory path for user-specific simulator runtimes.
    private func getHomeRuntimesPath() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent("Library/Developer/CoreSimulator/Profiles/Runtimes/").path
    }

    /// Parses a single `.simruntime` folder/bundle and extracts platform, version, and name information.
    ///
    /// - Parameter url: The file URL of the `.simruntime` bundle directory.
    /// - Returns: A populated `SimulatorRuntime` if parsing was successful, otherwise `nil`.
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

            // Deduce platform from bundle properties
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
                return "iOS" // fallback default
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
