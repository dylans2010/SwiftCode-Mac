import Foundation
import CryptoKit
import OSLog

// MARK: - Sound Installer

public final class SoundInstaller: Sendable {
    public static let shared = SoundInstaller()

    private let logger = Logger(subsystem: "com.dylans2010.SwiftCode-Mac", category: "SoundInstaller")

    private var userSoundsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Sounds", isDirectory: true)
    }

    private init() {}

    // MARK: - Public Installation API

    public struct IntegrationStatus: Sendable {
        public let installedCount: Int
        public let totalCount: Int
        public let isComplete: Bool
        public let directoryURL: URL
    }

    /// Check how many of the custom application sounds are installed in ~/Library/Sounds/
    public func systemSettingsStatus() -> IntegrationStatus {
        let destinationDir = userSoundsDirectory
        var installed = 0
        for sound in SoundCatalog.customSounds {
            let target = destinationDir.appendingPathComponent(sound.filename)
            if FileManager.default.fileExists(atPath: target.path) {
                installed += 1
            }
        }
        return IntegrationStatus(
            installedCount: installed,
            totalCount: SoundCatalog.customSounds.count,
            isComplete: installed >= SoundCatalog.customSounds.count,
            directoryURL: destinationDir
        )
    }

    /// Installs custom alert sounds into ~/Library/Sounds/ safely with clean, normal sound names.
    /// Also cleans up any legacy "SwiftCode_" prefixed files from ~/Library/Sounds/.
    @discardableResult
    public func installSoundsIfNeeded() -> [String: Bool] {
        var results: [String: Bool] = [:]
        let destinationDir = userSoundsDirectory

        // 1. Ensure ~/Library/Sounds directory exists with standard 0o755 permissions
        do {
            if !FileManager.default.fileExists(atPath: destinationDir.path) {
                try FileManager.default.createDirectory(
                    at: destinationDir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755]
                )
                logger.info("[SoundInstaller] Created directory: \(destinationDir.path)")
            } else {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationDir.path)
            }
        } catch {
            logger.error("[SoundInstaller] Failed to create ~/Library/Sounds directory: \(error.localizedDescription)")
            return results
        }

        // 2. Clean up any legacy "SwiftCode_*" files so macOS System Settings shows clean, normal sound names
        cleanupLegacyPrefixedSounds()

        // 3. Iterate through all custom application sounds and install with clean normal filenames
        for sound in SoundCatalog.customSounds {
            let success = installSound(sound, in: destinationDir)
            results[sound.filename] = success
        }

        return results
    }

    /// Automatically removes any legacy files beginning with "SwiftCode_" from ~/Library/Sounds/
    public func cleanupLegacyPrefixedSounds() {
        let destinationDir = userSoundsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: destinationDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files {
            let name = file.lastPathComponent
            if name.hasPrefix("SwiftCode_") {
                do {
                    try FileManager.default.removeItem(at: file)
                    logger.info("[SoundInstaller] Cleaned up legacy sound file: \(name)")
                } catch {
                    logger.warning("[SoundInstaller] Failed to remove legacy file \(name): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Safely uninstalls only custom application sounds from ~/Library/Sounds/.
    /// Leaves all other sounds in ~/Library/Sounds/ completely untouched.
    @discardableResult
    public func uninstallSounds() -> [String: Bool] {
        var results: [String: Bool] = [:]
        let destinationDir = userSoundsDirectory

        // Clean up legacy prefixed sounds as well
        cleanupLegacyPrefixedSounds()

        for sound in SoundCatalog.customSounds {
            let targetURL = destinationDir.appendingPathComponent(sound.filename)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                do {
                    try FileManager.default.removeItem(at: targetURL)
                    logger.info("[SoundInstaller] Removed: \(sound.filename)")
                    results[sound.filename] = true
                } catch {
                    logger.error("[SoundInstaller] Failed to remove \(sound.filename): \(error.localizedDescription)")
                    results[sound.filename] = false
                }
            } else {
                results[sound.filename] = true
            }

            if let legacy = sound.legacyFilename {
                let legURL = destinationDir.appendingPathComponent(legacy)
                if FileManager.default.fileExists(atPath: legURL.path) {
                    try? FileManager.default.removeItem(at: legURL)
                }
            }
        }

        return results
    }

    // MARK: - Internal Installation Logic

    private func installSound(_ sound: AppSound, in destinationDir: URL) -> Bool {
        // 1. Locate source asset in bundle, dev repo, or explicit URL
        let sourceURL: URL
        if let bundleURL = sound.bundleURL, FileManager.default.fileExists(atPath: bundleURL.path) {
            sourceURL = bundleURL
        } else if let devURL = sound.devRepoURL, FileManager.default.fileExists(atPath: devURL.path) {
            sourceURL = devURL
        } else if let resolved = sound.resolvedURL, FileManager.default.fileExists(atPath: resolved.path) {
            sourceURL = resolved
        } else {
            let repoSound = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Sounds/\(sound.legacyFilename ?? sound.filename)")
            if FileManager.default.fileExists(atPath: repoSound.path) {
                sourceURL = repoSound
            } else {
                logger.warning("[SoundInstaller] Sound resource not found for: \(sound.filename)")
                return false
            }
        }

        let destinationURL = destinationDir.appendingPathComponent(sound.filename)

        // 2. Check if already installed, identical, and permissions correct
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if isFileIdentical(sourceURL: sourceURL, destinationURL: destinationURL) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destinationURL.path)
                logger.debug("[SoundInstaller] Sound already up-to-date: \(sound.filename)")
                return true
            }
        }

        // 3. Perform atomic copy/replace
        let success = copyAtomically(from: sourceURL, to: destinationURL)
        if success {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destinationURL.path)
        }
        return success
    }

    private func isFileIdentical(sourceURL: URL, destinationURL: URL) -> Bool {
        guard let srcData = try? Data(contentsOf: sourceURL),
              let dstData = try? Data(contentsOf: destinationURL) else {
            return false
        }

        if srcData.count != dstData.count {
            return false
        }

        let srcHash = SHA256.hash(data: srcData)
        let dstHash = SHA256.hash(data: dstData)
        return srcHash == dstHash
    }

    private func copyAtomically(from sourceURL: URL, to destinationURL: URL) -> Bool {
        let tempURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".tmp_\(UUID().uuidString)_\(destinationURL.lastPathComponent)")

        do {
            // Write to temporary file in same directory for atomic replace
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: sourceURL, to: tempURL)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            }

            logger.info("[SoundInstaller] Successfully installed \(destinationURL.lastPathComponent)")
            return true
        } catch {
            logger.error("[SoundInstaller] Error installing \(destinationURL.lastPathComponent): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }
}
