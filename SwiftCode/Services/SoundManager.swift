import Foundation
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

// MARK: - Unified Sound Manager (AED-016 Synthesized Audio Router)

/// Backward-compatibility facade routing legacy sound play calls directly to AlertSoundPlayer.
/// Fully synthesized via AVAudioEngine and AVAudioPCMBuffer; zero NSSound, zero AudioServices, zero bundled audio assets.
@MainActor
public final class SoundManager: ObservableObject, SoundPlaying {
    public static let shared = SoundManager()

    private let logger = Logger(subsystem: "com.dylans2010.SwiftCode-Mac", category: "SoundManager")

    /// The sound ID currently playing (nil when idle). Observable for UI "Now Playing" indicators.
    @Published public private(set) var currentlyPlayingSoundID: String? = nil

    private var hoverPreviewTask: Task<Void, Never>? = nil

    private init() {}

    // MARK: - Public Playback API

    /// Play a sound directly via its AppSound specification
    @discardableResult
    public func play(_ sound: AppSound) -> Bool {
        guard sound.id != SoundCatalog.noneSoundID else {
            logger.debug("[SoundManager] 'None' sound selected; skipping playback.")
            return false
        }
        return play(soundID: sound.id)
    }

    /// Play a sound by its identifier, mapping seamlessly to the synthesized AlertTone library
    @discardableResult
    public func play(soundID: String) -> Bool {
        guard soundID != SoundCatalog.noneSoundID else {
            logger.debug("[SoundManager] 'None' sound selected; skipping playback.")
            return false
        }

        let tone = resolveTone(for: soundID)
        self.currentlyPlayingSoundID = soundID

        AlertSoundPlayer.shared.play(tone)

        // Clear currentlyPlayingSoundID after playback finishes
        let durationMs = tone.spec.totalDurationMs
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((durationMs + 60) * 1_000_000))
            if self.currentlyPlayingSoundID == soundID {
                self.currentlyPlayingSoundID = nil
            }
        }
        return true
    }

    /// Play the configured sound for an AppSoundCategory
    @discardableResult
    public func play(for category: AppSoundCategory) -> Bool {
        let tone: AlertTone
        switch category {
        case .notification: tone = .mention
        case .message:      tone = .messageReceived
        case .success:      tone = .buildSuccess
        case .error:        tone = .error
        case .complete:     tone = .taskComplete
        case .chill:        tone = .fileSaved
        case .vibe:         tone = .syncStarted
        case .satisfying:   tone = .syncComplete
        }

        self.currentlyPlayingSoundID = tone.rawValue
        AlertSoundPlayer.shared.play(tone)
        return true
    }

    /// Preview a sound in Settings UI
    public func preview(soundID: String) {
        hoverPreviewTask?.cancel()

        if currentlyPlayingSoundID == soundID {
            stopAll()
            return
        }

        stopAll()
        _ = play(soundID: soundID)
    }

    /// Preview a specific AppSound directly
    public func preview(_ sound: AppSound) {
        preview(soundID: sound.id)
    }

    /// Preview a sound triggered by mouse hover with an intentional debounce
    public func previewOnHover(soundID: String, delay: Double = 0.08) {
        hoverPreviewTask?.cancel()
        guard soundID != SoundCatalog.noneSoundID else { return }

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

    /// Stop all active alert sound playback
    public func stopAll() {
        hoverPreviewTask?.cancel()
        currentlyPlayingSoundID = nil
        AlertSoundPlayer.shared.stop()
    }

    // MARK: - Tone Resolution Helper

    private func resolveTone(for soundID: String) -> AlertTone {
        // Direct AlertTone case match
        if let direct = AlertTone(rawValue: soundID) {
            return direct
        }

        // Semantic mapping for legacy catalog identifiers
        let lower = soundID.lowercased()
        if lower.contains("success") || lower.contains("done") || lower.contains("ready") || lower.contains("complete") {
            return .buildSuccess
        } else if lower.contains("error") || lower.contains("fail") || lower.contains("caution") || lower.contains("attention") {
            return .error
        } else if lower.contains("message") || lower.contains("whisper") {
            return .messageReceived
        } else if lower.contains("ping") || lower.contains("notify") || lower.contains("signal") {
            return .mention
        } else if lower.contains("save") {
            return .fileSaved
        } else if lower.contains("sync") {
            return .syncComplete
        } else if lower.contains("git") {
            return .gitCommit
        } else if lower.contains("project") {
            return .projectOpened
        } else if lower.contains("chill") || lower.contains("vibe") || lower.contains("bloom") {
            return .taskComplete
        } else {
            return .mention
        }
    }
}
