import Foundation
import Observation
import OSLog

/// MainActor facade providing reactive observable state, user mute/volume awareness, and singleton playback dispatch
@Observable
@MainActor
public final class AlertSoundPlayer {
    public static let shared = AlertSoundPlayer()

    private let logger = Logger(subsystem: "com.swiftcode.mac", category: "AudioAlerts")
    private let soundLibrary = SoundLibrary.shared

    private let isMutedKey = "com.swiftcode.mac.alertSounds.isMuted"
    private let volumeKey = "com.swiftcode.mac.alertSounds.volume"

    /// Whether alert sounds are muted globally
    public var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: isMutedKey)
            if isMuted {
                stop()
            }
            logger.info("Alert sound mute state changed: \(self.isMuted)")
        }
    }

    /// Master volume level for alert sounds (0.0 to 1.0)
    public var volume: Float {
        didSet {
            let clamped = max(0.0, min(1.0, volume))
            if volume != clamped {
                volume = clamped
            }
            UserDefaults.standard.set(clamped, forKey: volumeKey)
        }
    }

    /// The tone currently being played (nil when idle)
    public private(set) var currentlyPlayingTone: AlertTone? = nil

    private var activePlaybackResetTask: Task<Void, Never>? = nil

    private init() {
        self.isMuted = UserDefaults.standard.bool(forKey: isMutedKey)
        let storedVolume = UserDefaults.standard.float(forKey: volumeKey)
        // Default to 80% volume if not previously configured
        self.volume = storedVolume > 0 ? storedVolume : 0.8
    }

    // MARK: - Public Playback API

    /// Plays a synthesized alert tone respecting master mute and volume levels
    public func play(_ tone: AlertTone) {
        guard !isMuted else {
            logger.debug("Playback skipped for '\(tone.displayName)' (muted)")
            return
        }

        activePlaybackResetTask?.cancel()
        currentlyPlayingTone = tone

        let toneVolume = self.volume
        let durationMs = tone.spec.totalDurationMs

        Task {
            await soundLibrary.play(tone, volume: toneVolume)
        }

        // Automatically clear currentlyPlayingTone after the note sequence finishes
        activePlaybackResetTask = Task { @MainActor in
            let delayNanos = UInt64((durationMs + 60.0) * 1_000_000.0)
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else { return }
            if self.currentlyPlayingTone == tone {
                self.currentlyPlayingTone = nil
            }
        }
    }

    /// Stops any ongoing alert playback immediately
    public func stop() {
        activePlaybackResetTask?.cancel()
        currentlyPlayingTone = nil
        Task {
            await soundLibrary.stop()
        }
    }

    /// Pre-warms the sound cache on a background priority task
    public func warmCache() {
        Task.detached(priority: .utility) {
            await SoundLibrary.shared.warmCache()
        }
    }
}
