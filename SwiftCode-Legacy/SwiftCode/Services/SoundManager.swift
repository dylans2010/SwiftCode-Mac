import Foundation
import AppKit
import AudioToolbox
import SwiftUI
import OSLog

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

@MainActor
public final class SoundManager: NSObject, ObservableObject, SoundPlaying, NSSoundDelegate {
    public static let shared = SoundManager()

    private let logger = Logger(subsystem: "com.dylans2010.SwiftCode-Mac", category: "SoundManager")

    @Published public private(set) var currentlyPlayingSoundID: String? = nil

    private var activeSounds: [NSSound] = []

    private var currentPlaybackToken = UUID()

    private var hoverPreviewTask: Task<Void, Never>? = nil

    private override init() {
        super.init()
        _ = SoundInstaller.shared.installSoundsIfNeeded()
    }

    @discardableResult
    public func play(_ sound: AppSound) -> Bool {
        guard sound.id != SoundCatalog.noneSoundID else {
            logger.debug("[SoundManager] 'None' sound selected; skipping playback.")
            return false
        }

        return executePlayback(for: sound)
    }

    @discardableResult
    public func play(soundID: String) -> Bool {
        guard soundID != SoundCatalog.noneSoundID else {
            logger.debug("[SoundManager] 'None' sound selected; skipping playback.")
            return false
        }

        if let sound = SoundCatalog.sound(for: soundID) {
            return play(sound)
        }

        if let directTone = AlertTone(rawValue: soundID) {
            self.currentlyPlayingSoundID = soundID
            AlertSoundPlayer.shared.play(directTone)
            let durationMs = directTone.spec.totalDurationMs
            let token = self.currentPlaybackToken
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((durationMs + 60) * 1_000_000))
                if self.currentPlaybackToken == token {
                    self.currentlyPlayingSoundID = nil
                }
            }
            return true
        }

        let tone = resolveTone(for: soundID)
        self.currentlyPlayingSoundID = soundID
        AlertSoundPlayer.shared.play(tone)
        let durationMs = tone.spec.totalDurationMs
        let token = self.currentPlaybackToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((durationMs + 60) * 1_000_000))
            if self.currentPlaybackToken == token {
                self.currentlyPlayingSoundID = nil
            }
        }
        return true
    }

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

    public func preview(soundID: String) {
        hoverPreviewTask?.cancel()

        if currentlyPlayingSoundID == soundID {
            stopAll()
            return
        }

        stopAll()
        _ = play(soundID: soundID)
    }

    public func preview(_ sound: AppSound) {
        hoverPreviewTask?.cancel()

        if currentlyPlayingSoundID == sound.id {
            stopAll()
            return
        }

        stopAll()
        _ = play(sound)
    }

    public func previewOnHover(soundID: String, delay: Double = 0.05) {
        hoverPreviewTask?.cancel()
        guard soundID != SoundCatalog.noneSoundID else { return }

        if currentlyPlayingSoundID == soundID { return }

        stopAll()

        hoverPreviewTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            _ = self.play(soundID: soundID)
        }
    }

    public func stopAll() {
        hoverPreviewTask?.cancel()
        hoverPreviewTask = nil
        currentPlaybackToken = UUID()

        for sound in activeSounds {
            sound.delegate = nil
            sound.stop()
        }
        activeSounds.removeAll()
        currentlyPlayingSoundID = nil
        AlertSoundPlayer.shared.stop()
    }

    private func executePlayback(for sound: AppSound) -> Bool {
        cleanupFinishedSounds()
        let playbackToken = UUID()
        self.currentPlaybackToken = playbackToken

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
                logger.warning("[SoundManager] NSSound.play() failed for URL: \(url.path)")
            }
        }

        let soundCandidates = [
            sound.displayName,
            (sound.filename as NSString).deletingPathExtension,
            (sound.legacyFilename as NSString?)?.deletingPathExtension
        ].compactMap { $0 }

        for name in soundCandidates {
            if let namedSound = NSSound(named: NSSound.Name(name)) {
                namedSound.delegate = self
                activeSounds.append(namedSound)
                self.currentlyPlayingSoundID = sound.id
                let success = namedSound.play()
                if success {
                    logger.debug("[SoundManager] Playing '\(sound.displayName)' via NSSound(named: \(name))")
                    return true
                }
            }
        }

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

        let tone = resolveTone(for: sound.id)
        self.currentlyPlayingSoundID = sound.id
        AlertSoundPlayer.shared.play(tone)
        let durationMs = tone.spec.totalDurationMs
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((durationMs + 60) * 1_000_000))
            if self.currentPlaybackToken == playbackToken {
                self.currentlyPlayingSoundID = nil
            }
        }
        return true
    }

    private func cleanupFinishedSounds() {
        activeSounds.removeAll(where: { !$0.isPlaying })
    }

    nonisolated public func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        Task { @MainActor in
            self.activeSounds.removeAll(where: { $0 === sound })
            if self.activeSounds.isEmpty {
                self.currentlyPlayingSoundID = nil
            }
        }
    }

    private func resolveTone(for soundID: String) -> AlertTone {
        if let direct = AlertTone(rawValue: soundID) {
            return direct
        }

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

public struct SoundHoverModifier: ViewModifier {
    let soundID: String
    let delay: Double

    public func body(content: Content) -> some View {
        content
            .onHover { isHovered in
                if isHovered {
                    SoundManager.shared.previewOnHover(soundID: soundID, delay: delay)
                }
            }
    }
}

public extension View {
    func soundHover(soundID: String, delay: Double = 0.05) -> some View {
        modifier(SoundHoverModifier(soundID: soundID, delay: delay))
    }
}
