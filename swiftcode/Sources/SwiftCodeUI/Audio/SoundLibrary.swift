import Foundation
import AVFoundation
import OSLog

public actor SoundLibrary {
    public static let shared = SoundLibrary()

    private let logger = Logger(subsystem: "com.swiftcode.mac", category: "AudioAlerts")
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var bufferCache: [AlertTone: AVAudioPCMBuffer] = [:]
    private var isEngineConfigured: Bool = false

    private init() {}

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

    @discardableResult
    public func play(_ tone: AlertTone, volume: Float = 1.0) -> Bool {
        guard ensureEngineRunning() else {
            logger.error("Cannot play tone \(tone.rawValue, privacy: .public): engine not running")
            return false
        }

        let pcmBuffer = getOrCreateBuffer(for: tone)

        playerNode.stop()
        playerNode.volume = max(0.0, min(1.0, volume))

        playerNode.scheduleBuffer(pcmBuffer, at: nil, options: []) {
        }

        playerNode.play()
        logger.debug("Dispatched playback for tone: \(tone.rawValue, privacy: .public) at volume \(volume)")
        return true
    }

    public func stop() {
        if playerNode.isPlaying {
            playerNode.stop()
            logger.debug("Alert audio playback stopped")
        }
    }

    public var isPlaying: Bool {
        playerNode.isPlaying
    }

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

    public func warmCache() {
        let start = DispatchTime.now()
        for tone in AlertTone.allCases {
            _ = getOrCreateBuffer(for: tone)
        }
        let end = DispatchTime.now()
        let totalMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        logger.info("Warmed all 22 alert tone buffers in cache in \(String(format: "%.2f", totalMs))ms")
    }

    public func clearCache() {
        bufferCache.removeAll()
        logger.info("Cleared alert tone buffer cache")
    }

    public var cachedMemoryFootprintBytes: Int {
        var totalBytes = 0
        for (_, buf) in bufferCache {
            totalBytes += Int(buf.frameLength) * 4
        }
        return totalBytes
    }
}
