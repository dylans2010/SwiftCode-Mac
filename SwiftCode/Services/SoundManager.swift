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
    func stopAll()
}

// MARK: - Unified Sound Manager

@MainActor
public final class SoundManager: NSObject, ObservableObject, SoundPlaying, NSSoundDelegate {
    public static let shared = SoundManager()

    private let logger = Logger(subsystem: "com.dylans2010.SwiftCode-Mac", category: "SoundManager")

    /// The sound ID currently playing (nil when idle). Observable for UI "Now Playing" indicators.
    @Published public private(set) var currentlyPlayingSoundID: String? = nil

    // Active NSSound instances
    private var activeSounds: [NSSound] = []

    // Token uniquely identifying the active playback session, preventing race conditions from stopped sounds
    private var currentPlaybackToken = UUID()

    // Hover task for smooth debounced hover-to-play previews
    private var hoverPreviewTask: Task<Void, Never>? = nil

    private override init() {
        super.init()
        // Ensure custom sounds are installed and available immediately
        _ = SoundInstaller.shared.installSoundsIfNeeded()
    }

    // MARK: - Public Playback API

    /// Play a sound directly via its AppSound specification
    @discardableResult
    public func play(_ sound: AppSound) -> Bool {
        guard sound.id != SoundCatalog.noneSoundID else {
            logger.debug("[SoundManager] 'None' sound selected; skipping playback.")
            return false
        }

        return executePlayback(for: sound)
    }

    /// Play a sound by its stable identifier (e.g. "custom.chill.soft_bloom", "system_glass").
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
            soundID = settings.completionSoundID
        case .chill:
            soundID = SoundCatalog.chillSoftBloom.id
        case .vibe:
            soundID = SoundCatalog.vibePulse.id
        case .satisfying:
            soundID = SoundCatalog.satisfyingPerfect.id
        }

        return play(soundID: soundID)
    }

    /// Preview a sound in the Settings UI (toggles playback if clicked again)
    public func preview(soundID: String) {
        hoverPreviewTask?.cancel()

        // If clicking the sound that is already playing, toggle it off
        if currentlyPlayingSoundID == soundID {
            stopAll()
            return
        }

        stopAll()
        _ = play(soundID: soundID)
    }

    /// Preview a specific AppSound directly
    public func preview(_ sound: AppSound) {
        hoverPreviewTask?.cancel()

        if currentlyPlayingSoundID == sound.id {
            stopAll()
            return
        }

        stopAll()
        _ = play(sound)
    }

    /// Preview a sound triggered by mouse hover with an intentional debounce
    public func previewOnHover(soundID: String, delay: Double = 0.08) {
        hoverPreviewTask?.cancel()
        guard soundID != SoundCatalog.noneSoundID else { return }

        // If this sound is already actively playing, let it continue
        if currentlyPlayingSoundID == soundID { return }

        hoverPreviewTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self.stopAll()
            _ = self.play(soundID: soundID)
        }
    }

    /// Stop all currently playing audio initiated by SoundManager
    public func stopAll() {
        hoverPreviewTask?.cancel()
        currentPlaybackToken = UUID()

        for sound in activeSounds {
            sound.delegate = nil
            sound.stop()
        }
        activeSounds.removeAll()
        currentlyPlayingSoundID = nil
    }

    // MARK: - Unified Resilient Audio Playback Pipeline

    private func executePlayback(for sound: AppSound) -> Bool {
        cleanupFinishedSounds()
        let playbackToken = UUID()
        self.currentPlaybackToken = playbackToken

        // 1. Primary Strategy: In-memory NSSound from resolved URL (loads data without file lock)
        if let url = sound.resolvedURL, FileManager.default.fileExists(atPath: url.path) {
            if let nsSound = NSSound(contentsOf: url, byReference: false) {
                nsSound.delegate = self
                activeSounds.append(nsSound)
                self.currentlyPlayingSoundID = sound.id
                let success = nsSound.play()
                if success {
                    logger.debug("[SoundManager] Playing '\(sound.displayName)' via URL (\(url.lastPathComponent))")
                    return true
                }
                logger.warning("[SoundManager] NSSound.play() returned false for URL: \(url.path)")
            }
        }

        // 2. Secondary Strategy: Named sound lookup in AppKit search paths
        let soundName = (sound.filename as NSString).deletingPathExtension
        if let namedSound = NSSound(named: NSSound.Name(soundName)) {
            namedSound.delegate = self
            activeSounds.append(namedSound)
            self.currentlyPlayingSoundID = sound.id
            let success = namedSound.play()
            if success {
                logger.debug("[SoundManager] Playing '\(sound.displayName)' via NSSound(named: \(soundName))")
                return true
            }
        }

        // 3. Tertiary Strategy: AudioServices alert channel (AudioServicesPlayAlertSound)
        if let url = sound.resolvedURL ?? (sound.source == .system ? URL(fileURLWithPath: "/System/Library/Sounds/\(sound.filename)") : nil),
           FileManager.default.fileExists(atPath: url.path) {
            var systemID: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(url as CFURL, &systemID)
            if status == noErr {
                self.currentlyPlayingSoundID = sound.id
                AudioServicesPlayAlertSoundWithCompletion(systemID) { [weak self, playbackToken] in
                    AudioServicesDisposeSystemSoundID(systemID)
                    Task { @MainActor in
                        if self?.currentPlaybackToken == playbackToken {
                            self?.currentlyPlayingSoundID = nil
                        }
                    }
                }
                logger.debug("[SoundManager] Playing '\(sound.displayName)' via AudioServicesPlayAlertSound")
                return true
            }
        }

        logger.error("[SoundManager] All audio strategies failed for sound: \(sound.displayName) (\(sound.filename))")
        if self.currentPlaybackToken == playbackToken {
            self.currentlyPlayingSoundID = nil
        }
        return false
    }

    private func cleanupFinishedSounds() {
        activeSounds.removeAll(where: { !$0.isPlaying })
    }

    // MARK: - NSSoundDelegate

    nonisolated public func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        Task { @MainActor in
            self.activeSounds.removeAll(where: { $0 === sound })
            if self.activeSounds.isEmpty {
                self.currentlyPlayingSoundID = nil
            }
        }
    }
}
