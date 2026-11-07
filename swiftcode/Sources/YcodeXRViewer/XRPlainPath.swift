import CYcodeOpenXR
import Foundation
import YcodeDisplayStream
import YcodeRemoteViewer

protocol XRPictureSink: AnyObject {
    func upload(eye: Int, pixels: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws
    func uploadNV12(eye: Int, y: UnsafePointer<UInt8>, uv: UnsafePointer<UInt8>, pitch: Int, width: Int, height: Int) throws
    func uploadYUV444(eye: Int, y: UnsafePointer<UInt8>, u: UnsafePointer<UInt8>, v: UnsafePointer<UInt8>, pitch: Int, width: Int, height: Int) throws
}

extension XRSession: XRPictureSink {}

final class XROffscreenSink: XRPictureSink {
    private var staging: UnsafeMutablePointer<UInt8>?
    private var size = 0
    private(set) var uploads = 0
    private(set) var busy: [Double] = []

    deinit { staging?.deallocate() }

    private func buffer(_ width: Int, _ height: Int) -> UnsafeMutablePointer<UInt8> {
        let need = width * height * 4
        if need != size {
            staging?.deallocate()
            staging = .allocate(capacity: need)
            size = need
        }
        return staging!
    }

    private func timed(_ body: () -> Void) {
        let t = viewerNanoseconds()
        body()
        uploads += 1
        busy.append(Double(viewerNanoseconds() - t) / 1e6)
    }

    func upload(eye: Int, pixels: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws {
        let d = buffer(width, height)
        timed { for r in 0..<height { memcpy(d + r * width * 4, pixels + r * bytesPerRow, width * 4) } }
    }

    func uploadNV12(eye: Int, y: UnsafePointer<UInt8>, uv: UnsafePointer<UInt8>, pitch: Int, width: Int, height: Int) throws {
        let d = buffer(width, height)
        timed { yxr_convert_nv12(y, uv, Int32(pitch), Int32(width), Int32(height), d, 1) }
    }

    func uploadYUV444(eye: Int, y: UnsafePointer<UInt8>, u: UnsafePointer<UInt8>, v: UnsafePointer<UInt8>, pitch: Int, width: Int, height: Int) throws {
        let d = buffer(width, height)
        timed { yxr_convert_yuv444(y, u, v, Int32(pitch), Int32(width), Int32(height), d, 1) }
    }

    var summary: String {
        let s = busy.sorted()
        guard !s.isEmpty else { return "offscreen uploads: none" }
        return String(format: "offscreen uploads: %d, each p50 %.1f / p99 %.1f / max %.1f ms", uploads, s[s.count / 2], s[min(s.count - 1, s.count * 99 / 100)], s.last!)
    }
}

final class XRPlainPath {
    private var shown: [XRView: UInt64] = [:]
    private(set) var plan = XRLayerPlan()
    private(set) var insetWaits = 0
    private(set) var leftCanvas: StreamCanvas?

    func update(_ viewer: XRViewer, into sink: XRPictureSink, anchor: XRStageAnchor, head: SpatialPose?, ahead: UInt64, log: (String) -> Void) {
        let o = viewer.options
        for v in [XRView.mono, .left, .right] {
            guard let entry = viewer.board.get(v), entry.sequence != shown[v], let canvas = viewer.client.canvas(for: v) else { continue }
            if o.foveaFraction > 0, viewer.inset(v)?.inset.frameSequence != entry.sequence,
               viewerNanoseconds() &- entry.decodedAt < 50_000_000 { insetWaits += 1; continue }
            let slot = v == .mono ? XRLayerPlan.monoSlot : (v == .right ? 1 : 0)
            if let failure = Self.upload(canvas, slot: slot, into: sink, onePlaneAtATime: o.uploadViaBGRX) { log("swiftcode-xr-viewer: \(failure)"); continue }
            let uploaded = viewerNanoseconds()
            shown[v] = entry.sequence
            var sample = XRLatencySample(received: entry.receivedAt, decoded: entry.decodedAt, uploaded: uploaded, display: uploaded + ahead)
            if let t = viewer.client.takeTiming(sequence: entry.sequence) {
                let clock = viewer.client.clock
                func map(_ ns: UInt64) -> UInt64 { ns == 0 ? 0 : clock.clientTime(server: ns) ?? 0 }
                (sample.recordSeen, sample.captureStart, sample.encodeEnd, sample.sendEnd) = (map(t.recordSeen), map(t.captureStart), map(t.encodeEnd), map(t.sendEnd))
            }
            let rendered: SpatialPose, fov: XRFieldOfView
            if let tag = entry.tag {
                rendered = anchor.fromStage(tag.pose)
                fov = tag.fov
                sample.poseSent = viewer.poseSent(tag.poseSequence) ?? 0
            } else {
                let (w, h) = viewer.guestSize
                rendered = head ?? .identity
                fov = .guest(width: w, height: h)
            }
            if viewer.depthView == nil {
                viewer.addLatency(sample)
                viewer.pictureShown(entry, sample)
            }
            plan.show(v, .init(sequence: entry.sequence, pose: rendered, fov: fov))
            if v != .right { leftCanvas = canvas }
        }
    }

    static func upload(_ canvas: StreamCanvas, slot: Int, into sink: XRPictureSink, onePlaneAtATime: Bool) -> Error? {
        if !onePlaneAtATime {
            let done: Error?? = canvas.withVideoPlanes { p, _ -> Error? in
                do {
                    if p.format == .yuv444, let v = p.v {
                        try sink.uploadYUV444(eye: slot, y: p.y, u: p.u, v: v, pitch: p.pitch, width: canvas.width, height: canvas.height)
                    } else {
                        try sink.uploadNV12(eye: slot, y: p.y, uv: p.u, pitch: p.pitch, width: canvas.width, height: canvas.height)
                    }
                    return nil
                } catch { return error }
            }
            if let done { return done }
        }
        return canvas.withPixels { base, bytesPerRow, _ in
            do { try sink.upload(eye: slot, pixels: base, width: canvas.width, height: canvas.height, bytesPerRow: bytesPerRow); return nil }
            catch { return error }
        }
    }
}
