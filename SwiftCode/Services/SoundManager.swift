import Foundation
import AppKit
import AudioToolbox
import OSLog

// MARK: - Sound Playing Protocol

@MainActor
public protocol SoundPlaying: AnyObject {
    @discardableResult
    func play(_ sound: AppSound) -> Bool
    @discardableResult
    func play(soundID: String) -> Bool
    @discardableResult
    func play(for category: AppSoundCategory) -> Bool
}

// MARK: - Unified Sound Manager

@MainActor
public final class SoundManager: ObservableObject, SoundPlaying {
    public static let shared = SoundManager()

    private let logger = Logger(subsystem: "com.dylans2010.SwiftCode-Mac", category: "SoundManager")

    // Active NSSound instances for custom/user playback and previews
    private var activeSounds: [NSSound] = []

    // AudioToolbox SystemSoundID cache for native system sounds
    private var systemSoundCache: [String: SystemSoundID] = [:]

    private init() {}

    deinit {
        // Dispose all cached AudioToolbox SystemSoundID resources
        for soundID in systemSoundCache.values {
            AudioServicesDisposeSystemSoundID(soundID)
        }
        systemSoundCache.removeAll()
    }

    // MARK: - Public Playback API

    /// Play a sound directly via its AppSound specification
    @discardableResult
    public func play(_ sound: AppSound) -> Bool {
        switch sound.source {
        case .system:
            return playSystemSound(sound)
        case .custom, .user:
            return playFileSound(sound)
        }
    }

    /// Play a sound by its stable identifier (e.g. "system_glass", "swiftcode_notification_a").
    /// If identifier is "none", skips playback cleanly.
    @discardableResult
    public func play(soundID: String) -> Bool {
        guard soundID != SoundCatalog.noneSoundID else {
            logger.debug("[SoundManager] 'None' sound selected; skipping playback.")
            return false
        }

        guard let sound = SoundCatalog.sound(for: soundID) else {
            logger.warning("[SoundManager] Unrecognized sound ID: \(soundID)")
            return false
        }

        return play(sound)
    }

    /// Play the user-configured sound for a category from AppSettings
    @discardableResult
    public func play(for category: AppSoundCategory) -> Bool {
        let settings = AppSettings.shared
        let soundID: String
        switch category {
        case .notification:
            soundID = settings.notificationSoundID
        case .message:
            soundID = settings.messageSoundID
        case .success:
            soundID = settings.successSoundID
        case .error:
            soundID = settings.errorSoundID
        case .complete:
            soundID = settings.notificationSoundID
        }

        return play(soundID: soundID)
    }

    /// Preview a sound in the Settings UI (stops any currently playing preview)
    public func preview(soundID: String) {
        stopAll()
        _ = play(soundID: soundID)
    }

    /// Preview a specific AppSound directly
    public func preview(_ sound: AppSound) {
        stopAll()
        _ = play(sound)
    }

    /// Stop all currently playing audio initiated by SoundManager
    public func stopAll() {
        for sound in activeSounds {
            sound.stop()
        }
        activeSounds.removeAll()
    }

    // MARK: - AudioToolbox Native System Sound Backend

    private func playSystemSound(_ sound: AppSound) -> Bool {
        // 1. If explicit URL or path exists, use AudioServices with caching
        if let url = sound.resolvedURL {
            let key = url.path
            if let cachedID = systemSoundCache[key] {
                AudioServicesPlaySystemSound(cachedID)
                return true
            }

            var newID: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(url as CFURL, &newID)
            if status == noErr {
                systemSoundCache[key] = newID
                AudioServicesPlaySystemSound(newID)
                return true
            } else {
                logger.warning("[SoundManager] AudioServicesCreateSystemSoundID failed with status \(status) for \(url.path)")
            }
        }

        // 2. Fallback to native NSSound(named:) for system sounds
        let soundName = (sound.filename as NSString).deletingPathExtension
        if let namedSound = NSSound(named: NSSound.Name(soundName)) {
            cleanupFinishedSounds()
            activeSounds.append(namedSound)
            return namedSound.play()
        }

        logger.error("[SoundManager] Failed to resolve native system sound: \(sound.displayName)")
        return false
    }

    // MARK: - Custom & User File Playback Backend (NSSound)

    private func playFileSound(_ sound: AppSound) -> Bool {
        if let url = sound.resolvedURL, let nsSound = NSSound(contentsOf: url, byReference: true) {
            cleanupFinishedSounds()
            activeSounds.append(nsSound)
            let success = nsSound.play()
            if !success {
                logger.warning("[SoundManager] NSSound.play() failed for URL: \(url.path)")
            }
            return success
        }

        // Fallback for custom sounds installed in ~/Library/Sounds/
        let soundName = (sound.filename as NSString).deletingPathExtension
        if let namedSound = NSSound(named: NSSound.Name(soundName)) {
            cleanupFinishedSounds()
            activeSounds.append(namedSound)
            return namedSound.play()
        }

        logger.error("[SoundManager] Could not find or decode sound asset: \(sound.filename)")
        return false
    }

    private func cleanupFinishedSounds() {
        activeSounds.removeAll(where: { !$0.isPlaying })
    }
}
