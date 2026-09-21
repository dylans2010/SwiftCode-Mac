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

    /// Installs SwiftCode's custom alert sounds into ~/Library/Sounds/ safely and idempotently.
    /// Does not touch or modify any third-party or system sound files.
    @discardableResult
    public func installSoundsIfNeeded() -> [String: Bool] {
        var results: [String: Bool] = [:]
        let destinationDir = userSoundsDirectory

        // 1. Ensure ~/Library/Sounds directory exists
        do {
            if !FileManager.default.fileExists(atPath: destinationDir.path) {
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)
                logger.info("[SoundInstaller] Created directory: \(destinationDir.path)")
            }
        } catch {
            logger.error("[SoundInstaller] Failed to create ~/Library/Sounds directory: \(error.localizedDescription)")
            return results
        }

        // 2. Iterate through all custom application sounds
        for sound in SoundCatalog.customSounds {
            let success = installSound(sound, in: destinationDir)
            results[sound.filename] = success
        }

        return results
    }

    /// Safely uninstalls only SwiftCode custom sounds from ~/Library/Sounds/.
    /// Leaves all other sounds in ~/Library/Sounds/ completely untouched.
    @discardableResult
    public func uninstallSounds() -> [String: Bool] {
        var results: [String: Bool] = [:]
        let destinationDir = userSoundsDirectory

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
        }

        return results
    }

    // MARK: - Internal Installation Logic

    private func installSound(_ sound: AppSound, in destinationDir: URL) -> Bool {
        // 1. Locate source asset in bundle or source directory
        let sourceURL: URL
        if let bundleURL = sound.bundleURL {
            sourceURL = bundleURL
        } else {
            let repoSound = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Sounds/\(sound.filename)")
            if FileManager.default.fileExists(atPath: repoSound.path) {
                sourceURL = repoSound
            } else {
                logger.warning("[SoundInstaller] Sound resource not found for: \(sound.filename)")
                return false
            }
        }

        let destinationURL = destinationDir.appendingPathComponent(sound.filename)

        // 2. Check if already installed and identical
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if isFileIdentical(sourceURL: sourceURL, destinationURL: destinationURL) {
                logger.debug("[SoundInstaller] Sound already up-to-date: \(sound.filename)")
                return true
            }
        }

        // 3. Perform atomic copy/replace
        return copyAtomically(from: sourceURL, to: destinationURL)
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
