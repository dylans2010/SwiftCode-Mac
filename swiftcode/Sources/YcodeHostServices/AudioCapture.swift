import Foundation

public final class AudioCaptureWriter {
    public let path: String
    public let sampleRate: Int
    public let channels: Int
    private let handle: FileHandle
    private var baseNs: UInt64?
    public private(set) var writtenFrames: Int64 = 0
    private var pending: [Float] = []
    private var framesSinceHeader: Int64 = 0
    public private(set) var blocks = 0
    public private(set) var nonZeroSamples = 0
    public private(set) var peak: Float = 0
    private let holdFrames: Int

    public init(path: String, sampleRate: Int, channels: Int) throws {
        guard FileManager.default.createFile(atPath: path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
        }
        guard let h = FileHandle(forWritingAtPath: path) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
        }
        self.path = path
        self.sampleRate = sampleRate
        self.channels = channels
        handle = h
        holdFrames = sampleRate / 4
        h.write(Data(Self.header(dataBytes: 0, sampleRate: sampleRate, channels: channels)))
    }

    public static func header(dataBytes: UInt32, sampleRate: Int, channels: Int) -> [UInt8] {
        func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
        func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
        let blockAlign = UInt16(channels * 2)
        return Array("RIFF".utf8) + le32(36 &+ dataBytes) + Array("WAVE".utf8) + Array("fmt ".utf8) + le32(16) + le16(1)
            + le16(UInt16(channels)) + le32(UInt32(sampleRate)) + le32(UInt32(sampleRate) * UInt32(blockAlign))
            + le16(blockAlign) + le16(16) + Array("data".utf8) + le32(dataBytes)
    }

    public func add(_ samples: [Float], at ns: UInt64) {
        let frames = samples.count / channels
        guard frames > 0 else { return }
        blocks += 1
        for s in samples where s != 0 {
            nonZeroSamples += 1
            peak = max(peak, abs(s))
        }
        if baseNs == nil { baseNs = ns }
        let end = writtenFrames + Int64(pending.count / channels)
        var position = ns >= baseNs! ? Int64((Double(ns - baseNs!) * Double(sampleRate) / 1e9).rounded()) : 0
        if position > end + Int64(sampleRate) {
            baseNs! += UInt64(Double(position - end) * 1e9 / Double(sampleRate))
            position = end
        }
        var first = 0
        if position < writtenFrames {
            first = Int(writtenFrames - position)
            if first >= frames { return }
            position = writtenFrames
        }
        let offset = Int(position - writtenFrames) * channels
        let needed = offset + (frames - first) * channels
        if pending.count < needed { pending += [Float](repeating: 0, count: needed - pending.count) }
        for i in 0..<((frames - first) * channels) { pending[offset + i] += samples[first * channels + i] }
        let pendingFrames = pending.count / channels
        if pendingFrames > holdFrames { write(frames: pendingFrames - holdFrames) }
    }

    private func write(frames: Int) {
        let n = min(frames, pending.count / channels)
        guard n > 0 else { return }
        var out = [UInt8]()
        out.reserveCapacity(n * channels * 2)
        for i in 0..<(n * channels) {
            let v = Int16(max(-1, min(1, pending[i])) * 32767)
            out.append(UInt8(truncatingIfNeeded: v))
            out.append(UInt8(truncatingIfNeeded: v >> 8))
        }
        pending.removeFirst(n * channels)
        handle.write(Data(out))
        writtenFrames += Int64(n)
        framesSinceHeader += Int64(n)
        if framesSinceHeader >= Int64(sampleRate) { updateHeader() }
    }

    private func updateHeader() {
        framesSinceHeader = 0
        let bytes = UInt32(clamping: writtenFrames * Int64(channels) * 2)
        let at = handle.offsetInFile
        handle.seek(toFileOffset: 0)
        handle.write(Data(Self.header(dataBytes: bytes, sampleRate: sampleRate, channels: channels)))
        handle.seek(toFileOffset: at)
    }

    public func flush() {
        write(frames: pending.count / channels)
        updateHeader()
        try? handle.synchronize()
    }

    public func close() {
        flush()
        try? handle.close()
    }
}
