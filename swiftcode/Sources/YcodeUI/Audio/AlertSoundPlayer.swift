import Foundation
import Observation
import OSLog
import YcodeXcodebuild

@Observable
@MainActor
public final class AlertSoundPlayer {
    public static let shared = AlertSoundPlayer()

    private let logger = Logger(subsystem: "com.swiftcode.mac", category: "AudioAlerts")
    private let soundLibrary = SoundLibrary.shared

    private let isMutedKey = "com.swiftcode.mac.alertSounds.isMuted"
    private let volumeKey = "com.swiftcode.mac.alertSounds.volume"

    public var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: isMutedKey)
            if isMuted {
                stop()
            }
            logger.info("Alert sound mute state changed: \(self.isMuted)")
        }
    }

    public var volume: Float {
        didSet {
            let clamped = max(0.0, min(1.0, volume))
            if volume != clamped {
                volume = clamped
            }
            UserDefaults.standard.set(clamped, forKey: volumeKey)
        }
    }

    public private(set) var currentlyPlayingTone: AlertTone? = nil

    private var activePlaybackResetTask: Task<Void, Never>? = nil

    private init() {
        self.isMuted = UserDefaults.standard.bool(forKey: isMutedKey)
        let storedVolume = UserDefaults.standard.float(forKey: volumeKey)
        self.volume = storedVolume > 0 ? storedVolume : 0.8
    }

    public static func installBuildSoundHook() {
        BuildAlertSoundHook.play = { sound in
            Task { @MainActor in
                AlertSoundPlayer.shared.play(sound == .buildSuccess ? .buildSuccess : .buildFailure)
            }
        }
    }

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

        activePlaybackResetTask = Task { @MainActor in
            let delayNanos = UInt64((durationMs + 60.0) * 1_000_000.0)
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else { return }
            if self.currentlyPlayingTone == tone {
                self.currentlyPlayingTone = nil
            }
        }
    }

    public func stop() {
        activePlaybackResetTask?.cancel()
        currentlyPlayingTone = nil
        Task {
            await soundLibrary.stop()
        }
    }

    public func warmCache() {
        Task.detached(priority: .utility) {
            await SoundLibrary.shared.warmCache()
        }
    }
}
