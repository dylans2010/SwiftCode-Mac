import Foundation
import AVFoundation

/// Pure audio synthesis engine generating melodic alert tones into `AVAudioPCMBuffer`
public struct ToneSynthesizer: Sendable {
    /// Standard professional audio sample rate (44.1 kHz)
    public static let sampleRate: Double = 44100.0

    /// Standard audio format: 44.1 kHz, Mono, 32-bit Floating Point
    public static var standardFormat: AVAudioFormat {
        // SAFETY: Standard 44.1kHz mono Float32 format is always supported by AVFoundation on macOS.
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    // MARK: - Synthesis API

    /// Synthesize an entire AlertTone into an in-memory `AVAudioPCMBuffer`
    public static func synthesize(_ tone: AlertTone) -> AVAudioPCMBuffer {
        return synthesize(spec: tone.spec)
    }

    /// Synthesize a raw ToneSpec into an in-memory `AVAudioPCMBuffer`
    public static func synthesize(spec: ToneSpec) -> AVAudioPCMBuffer {
        let format = standardFormat
        var allSamples: [Float] = []

        for (index, note) in spec.notes.enumerated() {
            // Generate samples for this individual note with its ADSR envelope
            let noteSamples = generateNoteSamples(
                frequency: note.frequencyHz,
                durationMs: note.durationMs,
                envelope: note.envelope
            )
            allSamples.append(contentsOf: noteSamples)

            // Insert silence gap between consecutive notes in multi-note phrases
            if index < spec.notes.count - 1 && spec.gapMs > 0 {
                let gapSampleCount = Int((spec.gapMs / 1000.0) * sampleRate)
                if gapSampleCount > 0 {
                    allSamples.append(contentsOf: [Float](repeating: 0.0, count: gapSampleCount))
                }
            }
        }

        let frameCount = AVAudioFrameCount(allSamples.count)
        // SAFETY: Allocating a valid PCM buffer using our standard 44.1kHz mono Float32 format and non-negative capacity.
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameCount, 1)) else {
            fatalError("[ToneSynthesizer] Failed to allocate AVAudioPCMBuffer with capacity \(frameCount)")
        }

        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            let channelPointer = channelData[0]
            for i in 0..<allSamples.count {
                channelPointer[i] = allSamples[i]
            }
        }

        return buffer
    }

    // MARK: - Note & Waveform Synthesis

    /// Generates Float32 samples for a single note using 70% sine fundamental + 30% triangle 2nd harmonic blend
    private static func generateNoteSamples(
        frequency: Double,
        durationMs: Double,
        envelope: EnvelopeSpec
    ) -> [Float] {
        let durationSec = durationMs / 1000.0
        let sampleCount = max(1, Int(durationSec * sampleRate))
        var samples = [Float](repeating: 0.0, count: sampleCount)

        // Waveform parameters
        let twoPi = 2.0 * Double.pi
        let fundamentalFreq = frequency
        let harmonicFreq = frequency * 2.0 // 2nd harmonic

        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate

            // 1. Fundamental Component: 70% sine wave
            let sineComponent = sin(twoPi * fundamentalFreq * t)

            // 2. Harmonic Component: 30% triangle wave at half amplitude on 2nd harmonic
            // Standard normalized triangle wave from -1.0 to 1.0
            let harmonicPhase = (harmonicFreq * t).truncatingRemainder(dividingBy: 1.0)
            let rawTriangle = 4.0 * abs(harmonicPhase - 0.5) - 1.0
            let triangleHalfAmp = 0.5 * rawTriangle

            // Additive blend: 70% fundamental + 30% triangle-overtone
            let blended = Float(0.70 * sineComponent + 0.30 * triangleHalfAmp)

            // 3. Compute ADSR envelope amplitude at time t
            let envAmp = envelopeAmplitude(at: t, duration: durationSec, spec: envelope)

            samples[i] = blended * envAmp
        }

        return samples
    }

    // MARK: - ADSR Envelope Calculation

    /// Evaluates the ADSR envelope amplitude [0.0 ... 1.0] at time `t` (seconds) within note duration `duration`
    private static func envelopeAmplitude(
        at t: Double,
        duration: Double,
        spec: EnvelopeSpec
    ) -> Float {
        guard t >= 0 && t <= duration else { return 0.0 }

        if spec.isLinearDecay {
            // Linear decay envelope with zero sustain (used by .criticalSystemError)
            let attackTime = min(spec.attackMs / 1000.0, duration * 0.25)
            if t < attackTime {
                return Float(t / max(attackTime, 0.0001))
            } else {
                let remainingTime = duration - attackTime
                let decayProgress = (t - attackTime) / max(remainingTime, 0.0001)
                return Float(max(0.0, 1.0 - decayProgress))
            }
        }

        // Standard ADSR calculation with adaptive duration scaling
        let targetAttack = max(0.001, spec.attackMs / 1000.0)
        let actualAttack = min(targetAttack, duration * 0.25)
        let timeAfterAttack = duration - actualAttack

        let targetDecay = max(0.001, spec.decayMs / 1000.0)
        let targetRelease = max(0.001, spec.releaseMs / 1000.0)

        let actualDecay: Double
        let actualRelease: Double
        let actualSustainDuration: Double

        if (targetDecay + targetRelease) > timeAfterAttack {
            // Scale decay and release proportionally to fit within the note duration
            let scale = timeAfterAttack / (targetDecay + targetRelease)
            actualDecay = targetDecay * scale
            actualRelease = targetRelease * scale
            actualSustainDuration = 0.0
        } else {
            actualDecay = targetDecay
            actualRelease = targetRelease
            actualSustainDuration = timeAfterAttack - (targetDecay + targetRelease)
        }

        let sustainLevel = Float(spec.sustainLevel)

        if t < actualAttack {
            // Attack phase: 0.0 -> 1.0
            return Float(t / actualAttack)
        } else if t < (actualAttack + actualDecay) {
            // Decay phase: 1.0 -> sustainLevel
            let decayProgress = (t - actualAttack) / actualDecay
            return Float(1.0 - (1.0 - Double(sustainLevel)) * decayProgress)
        } else if t < (actualAttack + actualDecay + actualSustainDuration) {
            // Sustain phase: holds steady at sustainLevel
            return sustainLevel
        } else {
            // Release phase: sustainLevel -> 0.0
            let releaseStart = actualAttack + actualDecay + actualSustainDuration
            let releaseProgress = (t - releaseStart) / max(actualRelease, 0.0001)
            return Float(max(0.0, Double(sustainLevel) * (1.0 - releaseProgress)))
        }
    }
}
