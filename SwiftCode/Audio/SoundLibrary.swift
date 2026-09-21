import Foundation
import AVFoundation
import OSLog

/// Concurrency-safe actor managing AVAudioEngine lifecycle, audio buffer caching, and playback dispatch
public actor SoundLibrary {
    public static let shared = SoundLibrary()

    private let logger = Logger(subsystem: "com.swiftcode.mac", category: "AudioAlerts")
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// In-memory precomputed buffer cache [AlertTone: AVAudioPCMBuffer]
    private var bufferCache: [AlertTone: AVAudioPCMBuffer] = [:]
    private var isEngineConfigured: Bool = false

    private init() {}

    // MARK: - Audio Graph Setup & Lifecycle

    private func setupAudioGraph() {
        guard !isEngineConfigured else { return }

        engine.attach(playerNode)
        let format = ToneSynthesizer.standardFormat

        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        isEngineConfigured = true
        logger.info("Audio engine graph successfully configured with standard 44.1kHz format")
    }

    private func ensureEngineRunning() -> Bool {
        setupAudioGraph()

        if !engine.isRunning {
            do {
                try engine.start()
                logger.info("AVAudioEngine started successfully")
            } catch {
                logger.error("Failed to start AVAudioEngine: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        return true
    }

    // MARK: - Playback API

    /// Plays the requested synthesized AlertTone
    @discardableResult
    public func play(_ tone: AlertTone, volume: Float = 1.0) -> Bool {
        guard ensureEngineRunning() else {
            logger.error("Cannot play tone \(tone.rawValue, privacy: .public): engine not running")
            return false
        }

        let pcmBuffer = getOrCreateBuffer(for: tone)

        // Stop any currently playing alert audio
        playerNode.stop()
        playerNode.volume = max(0.0, min(1.0, volume))

        playerNode.scheduleBuffer(pcmBuffer, at: nil, options: []) {
            // Buffer finished playing
        }

        playerNode.play()
        logger.debug("Dispatched playback for tone: \(tone.rawValue, privacy: .public) at volume \(volume)")
        return true
    }

    /// Halts active audio playback immediately
    public func stop() {
        if playerNode.isPlaying {
            playerNode.stop()
            logger.debug("Alert audio playback stopped")
        }
    }

    /// Whether the player node is currently outputting sound
    public var isPlaying: Bool {
        playerNode.isPlaying
    }

    // MARK: - Buffer Caching & Precomputation

    /// Returns the cached `AVAudioPCMBuffer` for a tone, synthesizing it on demand if not yet cached
    public func buffer(for tone: AlertTone) -> AVAudioPCMBuffer {
        return getOrCreateBuffer(for: tone)
    }

    private func getOrCreateBuffer(for tone: AlertTone) -> AVAudioPCMBuffer {
        if let existing = bufferCache[tone] {
            return existing
        }

        let start = DispatchTime.now()
        let synthesized = ToneSynthesizer.synthesize(tone)
        let end = DispatchTime.now()
        let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
        let ms = Double(nanos) / 1_000_000.0

        bufferCache[tone] = synthesized
        logger.debug("Synthesized and cached tone: \(tone.rawValue, privacy: .public) in \(String(format: "%.2f", ms))ms")
        return synthesized
    }

    /// Precomputes all 22 tone buffers into memory
    public func warmCache() {
        let start = DispatchTime.now()
        for tone in AlertTone.allCases {
            _ = getOrCreateBuffer(for: tone)
        }
        let end = DispatchTime.now()
        let totalMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        logger.info("Warmed all 22 alert tone buffers in cache in \(String(format: "%.2f", totalMs))ms")
    }

    /// Clears the in-memory buffer cache
    public func clearCache() {
        bufferCache.removeAll()
        logger.info("Cleared alert tone buffer cache")
    }

    /// Estimates the current cached buffer memory footprint in bytes
    public var cachedMemoryFootprintBytes: Int {
        var totalBytes = 0
        for (_, buf) in bufferCache {
            // Float32 = 4 bytes per frame per channel
            totalBytes += Int(buf.frameLength) * 4
        }
        return totalBytes
    }
}
