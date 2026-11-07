#if os(Linux) && arch(arm64)
import CYcodeCodec
import Foundation
import YcodeDisplayStream

final class DisplayAudioPipe: @unchecked Sendable {
    static let rate = 48_000, channels = 2, packetFrames = 240
    let codec: DisplayAudio.Codec
    private let send: (DisplayMessage) -> Bool
    private let cond = NSCondition()
    private var queue: [([Float], UInt64)] = []
    private var stopped = false
    private var encoder: UnsafeMutableRawPointer?
    private(set) var packetsSent = 0, silentSkipped = 0, bytesSent = 0, dropped = 0

    static func choose(client: [String]?) -> DisplayAudio.Codec? {
        guard let client, !client.isEmpty else { return nil }
        for c in client {
            if c == "opus", swiftcodec_opus_available() != 0 { return .opus }
            if c == "pcm" { return .pcm16 }
        }
        return nil
    }

    static var serverCodecs: [String] { (swiftcodec_opus_available() != 0 ? ["opus"] : []) + ["pcm"] }

    init(codec: DisplayAudio.Codec, bitrate: Int = 96_000, send: @escaping (DisplayMessage) -> Bool) {
        self.codec = codec
        self.send = send
        if codec == .opus { encoder = swiftcodec_opus_encoder_new(Int32(Self.rate), Int32(Self.channels), Int32(bitrate)) }
        let t = Thread { [weak self] in self?.run() }
        t.name = "display-audio"
        t.qualityOfService = .userInteractive
        t.start()
    }

    deinit { swiftcodec_opus_encoder_free(encoder) }

    func push(_ samples: [Float], at: UInt64) {
        cond.withLock {
            if queue.count > 20 { queue.removeFirst(); dropped += 1 }
            queue.append((samples, at))
            cond.signal()
        }
    }

    func stop() { cond.withLock { stopped = true; cond.signal() } }

    private func run() {
        var pending: [Float] = []
        var pendingAt: UInt64 = 0
        let frameNs = { (frames: Int) -> UInt64 in UInt64(frames) * 1_000_000_000 / UInt64(Self.rate) }
        var out = [UInt8](repeating: 0, count: 4000)
        while true {
            let batch = cond.withLock { () -> [([Float], UInt64)]? in
                while queue.isEmpty && !stopped { cond.wait() }
                if stopped { return nil }
                defer { queue.removeAll() }
                return queue
            }
            guard let batch else { return }
            for (samples, at) in batch {
                let expected = pendingAt &+ frameNs(pending.count / Self.channels)
                if pending.isEmpty || at > expected &+ 1_000_000 || expected > at &+ 1_000_000 {
                    pending.removeAll(keepingCapacity: true)
                    pendingAt = at
                }
                pending += samples
                while pending.count >= Self.packetFrames * Self.channels {
                    let n = Self.packetFrames * Self.channels
                    let at = pendingAt
                    let packet = pending.withUnsafeBufferPointer { Array($0[0..<n]) }
                    pending.removeFirst(n)
                    pendingAt &+= frameNs(Self.packetFrames)
                    if !packet.contains(where: { $0 != 0 }) { silentSkipped += 1; continue }
                    let data: [UInt8]
                    switch codec {
                    case .opus:
                        let k = packet.withUnsafeBufferPointer { swiftcodec_opus_encode(encoder, $0.baseAddress, Int32(Self.packetFrames), &out, Int32(out.count)) }
                        guard k > 0 else { continue }
                        data = Array(out[0..<Int(k)])
                    case .pcm16:
                        var d = [UInt8](repeating: 0, count: n * 2)
                        for i in 0..<n {
                            let v = Int16(max(-32768, min(32767, (packet[i] * 32767).rounded())))
                            d[2 * i] = UInt8(truncatingIfNeeded: v)
                            d[2 * i + 1] = UInt8(truncatingIfNeeded: v >> 8)
                        }
                        data = d
                    }
                    guard send(.audio(DisplayAudio(playTime: at, codec: codec, channels: Self.channels, frames: Self.packetFrames, data: data))) else {
                        return
                    }
                    packetsSent += 1
                    bytesSent += data.count
                }
            }
        }
    }
}
#endif
