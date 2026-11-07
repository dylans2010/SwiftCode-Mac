import Foundation
import SwiftCodeDisplayStream
import SwiftCodeHypervisor

#if os(Linux) && arch(arm64)

final class DisplayXRState: @unchecked Sendable {
    private let lock = NSLock()
    private var scheduler: XREyeScheduler
    private var lastSignature: UInt64?
    var mirrors: [XRView: DisplayMirror] = [:]
    var videos: [XRView: VideoFrameEncoder] = [:]
    var videoFailed = false
    let foveaFraction: Double
    let eyeYaw: Double
    private var foveaPoint: (u: Double, v: Double)?
    var lastInset: (u: Double, v: Double, time: UInt64, frame: UInt64)?
    var insetsSent = 0, insetBytes = 0, insetNs: UInt64 = 0

    func setFovea(u: Double, v: Double) {
        lock.withLock {
            if let p = foveaPoint, abs(p.u - u) > 0.02 || abs(p.v - v) > 0.02 { scheduler.noteInteraction(at: monotonicNanoseconds()) }
            foveaPoint = (u, v)
        }
    }

    func noteInteraction() { lock.withLock { scheduler.noteInteraction(at: monotonicNanoseconds()) } }
    var fovea: (u: Double, v: Double)? { lock.withLock { foveaPoint } }
    var needsFull: Set<XRView> = [.mono, .left, .right]
    let deliver: (_ viewPose: SpatialPose, _ devicePose: SpatialPose) -> Void
    private(set) var picturesSeen = 0, posesSent = 0, estimatedTags = 0, shownSettled = 0
    private var full: XRViews?

    static let guestRotation = ProcessInfo.processInfo.environment["SWIFTCODE_XR_GUEST_ROTATION"] != "0"

    static let defaultLatch = ProcessInfo.processInfo.environment["SWIFTCODE_XR_LATCH"].flatMap(Int.init) ?? 1
    static let defaultSettle = ProcessInfo.processInfo.environment["SWIFTCODE_XR_SETTLE_MS"].flatMap(Int.init)
    static let defaultSettleMax = ProcessInfo.processInfo.environment["SWIFTCODE_XR_SETTLE_MAX_MS"].flatMap(Int.init)
    static let renderDelay = ProcessInfo.processInfo.environment["SWIFTCODE_XR_RENDER_DELAY_MS"].flatMap(Int.init)

    init(request: XRClientRequest, deliver: @escaping (_ viewPose: SpatialPose, _ devicePose: SpatialPose) -> Void) {
        let mode = XREyeScheduler.Mode(rawValue: request.stereo) ?? .adaptive
        let settle = (request.settleMs ?? Self.defaultSettle).map { UInt64(min(2000, max(0, $0))) * 1_000_000 }
        scheduler = XREyeScheduler(mode: mode, latch: min(8, max(1, request.latch ?? Self.defaultLatch)), settleTime: settle,
                                   maxSettleTime: Self.defaultSettleMax.map { UInt64(min(4000, max(0, $0))) * 1_000_000 },
                                   renderDelay: Self.renderDelay.map { UInt64(min(2000, max(0, $0))) * 1_000_000 })
        self.deliver = deliver
        foveaFraction = min(0.9, max(0, request.foveaFraction ?? 0))
        eyeYaw = min(20, max(-20, request.eyeYawDegrees ?? 0))
    }

    var mode: XREyeScheduler.Mode { lock.withLock { scheduler.mode } }
    var latch: Int { lock.withLock { scheduler.latch } }
    var settleMilliseconds: UInt64 { lock.withLock { scheduler.effectiveSettle.least / 1_000_000 } }

    static func renderedPose(_ p: SpatialPose) -> SpatialPose {
        guestRotation ? p : SpatialPose(position: p.position, rotation: .identity)
    }

    func update(_ v0: XRViews) {
        let v = v0.canted(degrees: eyeYaw)
        var r = v
        (r.head, r.left, r.right) = (Self.renderedPose(v.head), Self.renderedPose(v.left), Self.renderedPose(v.right))
        let send = lock.withLock { () -> (XREyeScheduler.Send, SpatialPose)? in
            full = v
            scheduler.update(r, at: monotonicNanoseconds())
            if posesSent == 0, let s = scheduler.idle(at: monotonicNanoseconds()) { posesSent += 1; return (s, device(s)) }
            return nil
        }
        if let (s, head) = send { deliver(s.pose, head) }
    }

    func idle() {
        let send = lock.withLock { () -> (XREyeScheduler.Send, SpatialPose)? in
            guard let s = scheduler.idle(at: monotonicNanoseconds()) else { return nil }
            posesSent += 1
            return (s, device(s))
        }
        if let (s, head) = send { deliver(s.pose, head) }
    }

    func picture(signature: UInt64) -> (tag: XREyeScheduler.Send?, estimated: Bool)? {
        let r = lock.withLock { () -> (XREyeScheduler.Send?, Bool, (XREyeScheduler.Send, SpatialPose)?)? in
            if signature == lastSignature { return nil }
            lastSignature = signature
            picturesSeen += 1
            let r = scheduler.picture(at: monotonicNanoseconds())
            var send: (XREyeScheduler.Send, SpatialPose)?
            if let s = r.send { posesSent += 1; send = (s, device(s)) }
            guard r.show else { return nil }
            if r.estimated && r.tag != nil { estimatedTags += 1 }
            return (r.tag, r.estimated, send)
        }
        guard let r else { return nil }
        if let (s, head) = r.2 { deliver(s.pose, head) }
        return (r.0, r.1)
    }

    func due() -> (tag: XREyeScheduler.Send?, estimated: Bool)? {
        let r = lock.withLock { () -> (XREyeScheduler.Send, Bool, (XREyeScheduler.Send, SpatialPose)?)? in
            guard let d = scheduler.due(at: monotonicNanoseconds()) else { return nil }
            shownSettled += 1
            if d.estimated { estimatedTags += 1 }
            var send: (XREyeScheduler.Send, SpatialPose)?
            if let s = d.send { posesSent += 1; send = (s, device(s)) }
            return (d.tag, d.estimated, send)
        }
        guard let r else { return nil }
        if let (s, head) = r.2 { deliver(s.pose, head) }
        return (r.0, r.1)
    }

    private func device(_ s: XREyeScheduler.Send) -> SpatialPose {
        guard let f = full else { return s.pose }
        return f.eye(s.view)
    }

    func keyframe() { lock.withLock { needsFull = [.mono, .left, .right] } }

    func takeFull(_ v: XRView) -> Bool {
        lock.withLock { needsFull.remove(v) != nil }
    }

    var summary: String {
        lock.withLock { "\(scheduler.mode.rawValue), render delay \(scheduler.effectiveRenderDelay / 1_000_000) ms, settle \(scheduler.effectiveSettle.least / 1_000_000)–\(scheduler.effectiveSettle.most / 1_000_000) ms, picture interval \(Int(scheduler.pictureInterval / 1e6)) ms, camera rotation \(Self.guestRotation ? "sent" : "not sent"): \(picturesSeen) pictures, \(shownSettled) settled eye pictures, \(posesSent) poses, \(estimatedTags) estimated tags"
            + (foveaFraction > 0 ? String(format: "; foveated %.0f%%: %d insets, %.0f KB each, %.1f ms each", foveaFraction * 100, insetsSent,
                                          insetsSent > 0 ? Double(insetBytes) / 1000 / Double(insetsSent) : 0,
                                          insetsSent > 0 ? Double(insetNs) / 1e6 / Double(insetsSent) : 0) : "") }
    }
}

#endif
