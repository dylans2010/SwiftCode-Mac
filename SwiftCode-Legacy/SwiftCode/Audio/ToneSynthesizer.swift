import Foundation
import AVFoundation

public struct ToneSynthesizer: Sendable {
    public static let sampleRate: Double = 44100.0

    public static var standardFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    public static func synthesize(_ tone: AlertTone) -> AVAudioPCMBuffer {
        return synthesize(spec: tone.spec)
    }

    public static func synthesize(spec: ToneSpec) -> AVAudioPCMBuffer {
        let format = standardFormat
        var allSamples: [Float] = []

        for (index, note) in spec.notes.enumerated() {
            let noteSamples = generateNoteSamples(
                frequency: note.frequencyHz,
                durationMs: note.durationMs,
                envelope: note.envelope
            )
            allSamples.append(contentsOf: noteSamples)

            if index < spec.notes.count - 1 && spec.gapMs > 0 {
                let gapSampleCount = Int((spec.gapMs / 1000.0) * sampleRate)
                if gapSampleCount > 0 {
                    allSamples.append(contentsOf: [Float](repeating: 0.0, count: gapSampleCount))
                }
            }
        }

        let frameCount = AVAudioFrameCount(allSamples.count)
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

    private static func generateNoteSamples(
        frequency: Double,
        durationMs: Double,
        envelope: EnvelopeSpec
    ) -> [Float] {
        let durationSec = durationMs / 1000.0
        let sampleCount = max(1, Int(durationSec * sampleRate))
        var samples = [Float](repeating: 0.0, count: sampleCount)

        let twoPi = 2.0 * Double.pi
        let fundamentalFreq = frequency
        let harmonicFreq = frequency * 2.0

        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate

            let sineComponent = sin(twoPi * fundamentalFreq * t)

            let harmonicPhase = (harmonicFreq * t).truncatingRemainder(dividingBy: 1.0)
            let rawTriangle = 4.0 * abs(harmonicPhase - 0.5) - 1.0
            let triangleHalfAmp = 0.5 * rawTriangle

            let blended = Float(0.70 * sineComponent + 0.30 * triangleHalfAmp)

            let envAmp = envelopeAmplitude(at: t, duration: durationSec, spec: envelope)

            samples[i] = blended * envAmp
        }

        return samples
    }

    private static func envelopeAmplitude(
        at t: Double,
        duration: Double,
        spec: EnvelopeSpec
    ) -> Float {
        guard t >= 0 && t <= duration else { return 0.0 }

        if spec.isLinearDecay {
            let attackTime = min(spec.attackMs / 1000.0, duration * 0.25)
            if t < attackTime {
                return Float(t / max(attackTime, 0.0001))
            } else {
                let remainingTime = duration - attackTime
                let decayProgress = (t - attackTime) / max(remainingTime, 0.0001)
                return Float(max(0.0, 1.0 - decayProgress))
            }
        }

        let targetAttack = max(0.001, spec.attackMs / 1000.0)
        let actualAttack = min(targetAttack, duration * 0.25)
        let timeAfterAttack = duration - actualAttack

        let targetDecay = max(0.001, spec.decayMs / 1000.0)
        let targetRelease = max(0.001, spec.releaseMs / 1000.0)

        let actualDecay: Double
        let actualRelease: Double
        let actualSustainDuration: Double

        if (targetDecay + targetRelease) > timeAfterAttack {
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
            return Float(t / actualAttack)
        } else if t < (actualAttack + actualDecay) {
            let decayProgress = (t - actualAttack) / actualDecay
            return Float(1.0 - (1.0 - Double(sustainLevel)) * decayProgress)
        } else if t < (actualAttack + actualDecay + actualSustainDuration) {
            return sustainLevel
        } else {
            let releaseStart = actualAttack + actualDecay + actualSustainDuration
            let releaseProgress = (t - releaseStart) / max(actualRelease, 0.0001)
            return Float(max(0.0, Double(sustainLevel) * (1.0 - releaseProgress)))
        }
    }
}
