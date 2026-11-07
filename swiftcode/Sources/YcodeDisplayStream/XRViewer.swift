import Foundation

public struct XRStageAnchor: Equatable, Sendable {
    public var origin: SpatialVector
    public var yaw: Double

    public init(origin: SpatialVector = .zero, yaw: Double = 0) { (self.origin, self.yaw) = (origin, yaw) }

    public init(head: SpatialPose) {
        let f = head.forward
        let horizontal = (f.x * f.x + f.z * f.z).squareRoot()
        self.init(origin: head.position, yaw: horizontal > 1e-6 ? atan2(-f.x, -f.z) : 0)
    }

    var rotation: SpatialQuaternion { SpatialQuaternion(axis: SpatialVector(0, 1, 0), radians: yaw) }

    public func toStage(_ p: SpatialPose) -> SpatialPose {
        let inv = rotation.conjugate
        return SpatialPose(position: inv.rotate(p.position - origin), rotation: (inv * p.rotation).normalized)
    }

    public func toStage(point: SpatialVector) -> SpatialVector { rotation.conjugate.rotate(point - origin) }

    public func toStage(direction: SpatialVector) -> SpatialVector { rotation.conjugate.rotate(direction) }

    public func fromStage(point: SpatialVector) -> SpatialVector { origin + rotation.rotate(point) }
    public func fromStage(direction: SpatialVector) -> SpatialVector { rotation.rotate(direction) }

    public func fromStage(_ p: SpatialPose) -> SpatialPose {
        SpatialPose(position: origin + rotation.rotate(p.position), rotation: (rotation * p.rotation).normalized)
    }
}

public struct XRFieldOfView: Equatable, Sendable, Codable {
    public var left: Double, right: Double, up: Double, down: Double

    public init(left: Double, right: Double, up: Double, down: Double) { (self.left, self.right, self.up, self.down) = (left, right, up, down) }

    public static func guest(width: Int, height: Int) -> XRFieldOfView {
        let t = width > 0 ? Double(height) / Double(width) : 0.5625
        return XRFieldOfView(left: -.pi / 4, right: .pi / 4, up: atan(t), down: -atan(t))
    }

    public var tangents: (left: Double, right: Double, up: Double, down: Double) { (tan(left), tan(right), tan(up), tan(down)) }

    public init(tangentLeft l: Double, right r: Double, up u: Double, down d: Double) {
        self.init(left: atan(l), right: atan(r), up: atan(u), down: atan(d))
    }
}

public struct XRViews: Equatable, Sendable {
    public var sequence: UInt32
    public var stereo: Bool
    public var head: SpatialPose
    public var left: SpatialPose
    public var right: SpatialPose

    public init(sequence: UInt32, stereo: Bool, head: SpatialPose, left: SpatialPose, right: SpatialPose) {
        (self.sequence, self.stereo, self.head, self.left, self.right) = (sequence, stereo, head, left, right)
    }

    public func eye(_ v: XRView) -> SpatialPose {
        switch v {
        case .mono: head
        case .left: left
        case .right: right
        }
    }
}

public enum XRView: UInt8, Sendable, Codable, CaseIterable {
    case mono = 0, left = 1, right = 2

    public var other: XRView {
        switch self {
        case .mono: .mono
        case .left: .right
        case .right: .left
        }
    }
}

public struct XRFrameView: Equatable, Sendable {
    public var frameSequence: UInt64
    public var view: XRView
    public var estimated: Bool
    public var latch: UInt16
    public var poseSequence: UInt32
    public var pose: SpatialPose
    public var fov: XRFieldOfView
    public var guestFrame: UInt64

    public init(frameSequence: UInt64, view: XRView, estimated: Bool = false, latch: UInt16, poseSequence: UInt32,
                pose: SpatialPose, fov: XRFieldOfView, guestFrame: UInt64) {
        (self.frameSequence, self.view, self.estimated, self.latch, self.poseSequence) = (frameSequence, view, estimated, latch, poseSequence)
        (self.pose, self.fov, self.guestFrame) = (pose, fov, guestFrame)
    }
}

public struct XRInset: Equatable, Sendable {
    public var frameSequence: UInt64
    public var view: XRView
    public var encoding: DisplayEncoding
    public var x: Int, y: Int, width: Int, height: Int
    public var fullWidth: Int, fullHeight: Int
    public var data: [UInt8]

    public init(frameSequence: UInt64, view: XRView, encoding: DisplayEncoding, x: Int, y: Int, width: Int, height: Int,
                fullWidth: Int, fullHeight: Int, data: [UInt8]) {
        (self.frameSequence, self.view, self.encoding) = (frameSequence, view, encoding)
        (self.x, self.y, self.width, self.height, self.fullWidth, self.fullHeight, self.data) = (x, y, width, height, fullWidth, fullHeight, data)
    }

    public static func rect(u: Double, v: Double, width w: Int, height h: Int, fraction: Double) -> (x: Int, y: Int, width: Int, height: Int) {
        let iw = max(16, min(w, Int(Double(w) * fraction) / 16 * 16)), ih = max(16, min(h, Int(Double(h) * fraction) / 16 * 16))
        let cx = Int((min(max(u, 0), 1) * Double(w)).rounded()), cy = Int((min(max(v, 0), 1) * Double(h)).rounded())
        let x = min(max(0, (cx - iw / 2) / 16 * 16), w - iw), y = min(max(0, (cy - ih / 2) / 16 * 16), h - ih)
        return (x, y, iw, ih)
    }

    public static func fov(of r: (x: Int, y: Int, width: Int, height: Int), in fov: XRFieldOfView, width w: Int, height h: Int) -> XRFieldOfView {
        let t = fov.tangents
        func tx(_ px: Int) -> Double { t.left + (t.right - t.left) * Double(px) / Double(w) }
        func ty(_ py: Int) -> Double { t.up - (t.up - t.down) * Double(py) / Double(h) }
        return XRFieldOfView(tangentLeft: tx(r.x), right: tx(r.x + r.width), up: ty(r.y), down: ty(r.y + r.height))
    }

    public static func point(gaze d: SpatialVector, fov: XRFieldOfView) -> (u: Double, v: Double)? {
        guard d.z < -1e-6 else { return nil }
        let t = fov.tangents
        let x = d.x / -d.z, y = d.y / -d.z
        let u = (x - t.left) / (t.right - t.left), v = (t.up - y) / (t.up - t.down)
        guard u > -0.5, u < 1.5, v > -0.5, v < 1.5 else { return nil }
        return (min(max(u, 0), 1), min(max(v, 0), 1))
    }
}

extension XRViews {
    public func canted(degrees: Double) -> XRViews {
        guard degrees != 0 else { return self }
        let a = degrees * .pi / 180
        var v = self
        v.left.rotation = (left.rotation * SpatialQuaternion(axis: SpatialVector(0, 1, 0), radians: a)).normalized
        v.right.rotation = (right.rotation * SpatialQuaternion(axis: SpatialVector(0, 1, 0), radians: -a)).normalized
        return v
    }
}

public struct XREyeScheduler: Sendable {
    public enum Mode: String, Sendable { case mono, alternate, adaptive }

    public struct Send: Equatable, Sendable {
        public var view: XRView
        public var pose: SpatialPose
        public var poseSequence: UInt32
        public var picture: UInt64
        public var time: UInt64
    }

    public var mode: Mode
    public var latch: Int
    public var renderDelay: UInt64 = 0
    public private(set) var pictureInterval: Double = 43_000_000
    private var lastPictureTime: UInt64?
    public var poseDeadband = (metres: 0.0005, radians: 0.05 * Double.pi / 180)
    private var lastSentHead: SpatialPose?

    public var effectiveRenderDelay: UInt64 {
        renderDelay > 0 ? renderDelay : UInt64(min(400_000_000, max(60_000_000, 6 * pictureInterval)))
    }
    public var settleTime: UInt64 = 0
    public var quietTime: UInt64 = 60_000_000
    public var maxSettleTime: UInt64 = 0
    public var effectiveSettle: (least: UInt64, most: UInt64) {
        let least = settleTime > 0 ? settleTime : UInt64(max(250_000_000, 6 * pictureInterval))
        let most = maxSettleTime > 0 ? max(maxSettleTime, least) : least + UInt64(max(170_000_000, 4 * pictureInterval))
        return (least, most)
    }
    public var stillDistance = 0.015, stillAngle = 1.5 * Double.pi / 180
    public var stillTime: UInt64 = 300_000_000
    public var minimumInterval: UInt64 = 16_000_000

    public private(set) var views: XRViews?
    public private(set) var pictures: UInt64 = 0
    private var sent: [Send] = []
    private var lastSent: Send?
    private var viewsChanged = false
    private var lastChange: UInt64 = 0
    private var changedSinceSend = false
    private var motionHead: SpatialPose?
    private var lastMotion: UInt64 = 0

    public init(mode: Mode, latch: Int = 1, settleTime: UInt64? = nil, maxSettleTime: UInt64? = nil, renderDelay: UInt64? = nil) {
        self.mode = mode
        self.latch = max(1, latch)
        if let renderDelay { self.renderDelay = renderDelay }
        if let settleTime { self.settleTime = settleTime }
        if let maxSettleTime { self.maxSettleTime = maxSettleTime }
    }

    public mutating func update(_ v: XRViews, at time: UInt64 = 0) {
        if let s = lastSentHead {
            let moved = (v.head.position - s.position).length
            let turned = 2 * acos(min(1, abs(s.rotation.x * v.head.rotation.x + s.rotation.y * v.head.rotation.y
                                                + s.rotation.z * v.head.rotation.z + s.rotation.w * v.head.rotation.w)))
            if moved > poseDeadband.metres || turned > poseDeadband.radians { viewsChanged = true }
        } else {
            viewsChanged = true
        }
        views = v
        if let m = motionHead {
            let moved = (v.head.position - m.position).length
            let turned = 2 * acos(min(1, abs(m.rotation.x * v.head.rotation.x + m.rotation.y * v.head.rotation.y
                                                + m.rotation.z * v.head.rotation.z + m.rotation.w * v.head.rotation.w)))
            if moved > stillDistance || turned > stillAngle { motionHead = v.head; lastMotion = time }
        } else {
            motionHead = v.head
            lastMotion = time
        }
    }

    public mutating func noteInteraction(at time: UInt64) { lastMotion = max(lastMotion, time) }

    public func effectiveMode(at time: UInt64) -> Mode {
        guard mode == .adaptive else { return mode }
        return time &- lastMotion >= stillTime ? .alternate : .mono
    }

    public mutating func picture(at time: UInt64) -> (tag: Send?, estimated: Bool, send: Send?, show: Bool) {
        pictures += 1
        if let l = lastPictureTime, time > l { pictureInterval = 0.9 * pictureInterval + 0.1 * Double(min(time - l, 500_000_000)) }
        lastPictureTime = time
        lastChange = time
        changedSinceSend = true
        guard mode == .mono || (mode == .adaptive && (lastSent?.view ?? .mono) == .mono) else { return (nil, false, nil, false) }
        let tag = self.tag(at: time)
        let send = effectiveMode(at: time) == .mono ? next(at: time, force: false, view: .mono) : nil
        return (tag?.view == .mono ? tag : nil, tag == nil, send, true)
    }

    public mutating func due(at time: UInt64) -> (tag: Send, estimated: Bool, send: Send?)? {
        guard mode != .mono, let l = lastSent, l.view != .mono else { return nil }
        let age = time &- l.time
        let (least, most) = effectiveSettle
        guard age >= least else { return nil }
        let quiet = time &- lastChange >= quietTime
        guard (changedSinceSend && quiet) || age >= most else { return nil }
        let estimated = !changedSinceSend || !quiet
        if effectiveMode(at: time) == .mono { return (l, estimated, next(at: time, force: true, view: .mono)) }
        return (l, estimated, next(at: time, force: true))
    }

    public mutating func idle(at time: UInt64) -> Send? {
        guard views != nil else { return nil }
        switch mode {
        case .mono:
            guard viewsChanged else { return nil }
            if let l = lastSent, time &- l.time < minimumInterval { return nil }
            return next(at: time, force: true)
        case .alternate:
            return lastSent == nil ? next(at: time, force: true) : nil
        case .adaptive:
            if effectiveMode(at: time) == .mono {
                let eyeInFlight = lastSent.map { $0.view != .mono } ?? false
                guard viewsChanged || lastSent == nil || eyeInFlight else { return nil }
                if !eyeInFlight, let l = lastSent, time &- l.time < minimumInterval { return nil }
                return next(at: time, force: true, view: .mono)
            }
            guard let l = lastSent else { return next(at: time, force: true) }
            guard l.view == .mono, time &- l.time >= effectiveSettle.least else { return nil }
            return next(at: time, force: true, view: .left)
        }
    }

    public func tag(at time: UInt64) -> Send? {
        let delay = effectiveRenderDelay
        return sent.last { time &- $0.time >= delay && $0.time <= time } ?? sent.first
    }

    public func tag(for picture: UInt64) -> Send? {
        guard picture >= UInt64(latch) else { return nil }
        let limit = picture - UInt64(latch)
        return sent.last { $0.picture <= limit }
    }

    private mutating func next(at time: UInt64, force: Bool, view chosen: XRView? = nil) -> Send? {
        guard let v = views, force || viewsChanged else { return nil }
        let view: XRView
        if let chosen { view = chosen } else {
            switch mode {
            case .mono: view = .mono
            case .alternate, .adaptive: view = (lastSent?.view ?? .right) == .left ? .right : .left
            }
        }
        let s = Send(view: view, pose: v.eye(view), poseSequence: v.sequence, picture: pictures, time: time)
        sent.append(s)
        if sent.count > 64 { sent.removeFirst(sent.count - 64) }
        lastSent = s
        lastSentHead = v.head
        viewsChanged = false
        changedSinceSend = false
        return s
    }
}

public struct XROneEuro: Sendable {
    public var minCutoff: Double, beta: Double, derivativeCutoff: Double
    private var x: Double?, dx = 0.0, last: Double?

    public init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 1) {
        (self.minCutoff, self.beta, self.derivativeCutoff) = (minCutoff, beta, derivativeCutoff)
    }

    static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    public mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let px = x, let pt = last, time > pt else { x = value; last = time; return value }
        let dt = min(0.1, time - pt)
        last = time
        let d = (value - px) / dt
        dx += Self.alpha(derivativeCutoff, dt) * (d - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let v = px + Self.alpha(cutoff, dt) * (value - px)
        x = v
        return v
    }

    public mutating func reset() { x = nil; last = nil; dx = 0 }
}

public struct XRGazeStats: Sendable, Equatable {
    public var samples = 0, dropouts = 0, saccades = 0, fixationSamples = 0
    public var rawStepSq = 0.0, residualSq = 0.0
    public var rawJitterDegrees: Double { fixationSamples > 0 ? (rawStepSq / Double(fixationSamples)).squareRoot() : 0 }
    public var filteredResidualDegrees: Double { fixationSamples > 0 ? (residualSq / Double(fixationSamples)).squareRoot() : 0 }
    public var lagSq = [0.0, 0.0, 0.0], lagSamples = [0, 0, 0]
    public func lagDegrees(_ band: Int) -> Double { lagSamples[band] > 0 ? (lagSq[band] / Double(lagSamples[band])).squareRoot() : 0 }
    public var rayStepSq = 0.0, raySteps = 0
    public var rayJitterDegrees: Double { raySteps > 0 ? (rayStepSq / Double(raySteps)).squareRoot() : 0 }
    public var cellChanges = 0
    public var heldFrames = 0, longestDropout = 0.0, rewinds = 0, frozenFrames = 0
    public var description: String {
        String(format: "gaze: %d samples, %d dropouts (%.1f %%, longest %.0f ms, %d frames held on the last ray), %d saccades; while fixating (%d samples) frame-to-frame %.2f° RMS, filter removed %.2f° RMS; "
               + "ray behind the eye %.2f° RMS under 100 ms after a saccade, %.2f° to 300 ms, %.2f° later; ray steps %.3f° RMS; ray changed 3° cell %d times; pinches rewound %d, frames frozen by a pinch %d",
               samples, dropouts, samples + dropouts > 0 ? 100 * Double(dropouts) / Double(samples + dropouts) : 0, longestDropout * 1000, heldFrames, saccades, fixationSamples,
               rawJitterDegrees, filteredResidualDegrees, lagDegrees(0), lagDegrees(1), lagDegrees(2), rayJitterDegrees, cellChanges, rewinds, frozenFrames)
    }
}

public struct XRHysteresis: Equatable, Sendable {
    public var on: Double, off: Double
    public var below: Bool
    public private(set) var state = false

    public init(on: Double, off: Double, below: Bool) { (self.on, self.off, self.below) = (on, off, below) }

    public static func fingerPinch() -> XRHysteresis { XRHysteresis(on: 0.020, off: 0.035, below: true) }
    public static func trigger() -> XRHysteresis { XRHysteresis(on: 0.7, off: 0.4, below: false) }
    public static func pointing() -> XRHysteresis { XRHysteresis(on: 0.92, off: 0.85, below: false) }

    @discardableResult
    public mutating func update(_ v: Double) -> Bool {
        if below { state = state ? v < off : v < on } else { state = state ? v > off : v > on }
        return state
    }

    public mutating func reset() { state = false }
}

public struct XRHandJoints: Equatable, Sendable, Codable {
    public static let palm = 0, wrist = 1, thumbTip = 5, indexMetacarpal = 6, indexProximal = 7, indexIntermediate = 8,
                      indexDistal = 9, indexTip = 10, middleTip = 15

    public var poses: [SpatialPose]
    public var valid: UInt32
    public var radii: [Double]?

    public init(poses: [SpatialPose], valid: UInt32 = 0x3FF_FFFF, radii: [Double]? = nil) { (self.poses, self.valid, self.radii) = (poses, valid, radii) }

    public func has(_ j: Int) -> Bool { j < poses.count && valid & (1 << UInt32(j)) != 0 }

    public var pinchDistance: Double? {
        guard has(Self.thumbTip), has(Self.indexTip) else { return nil }
        return (poses[Self.thumbTip].position - poses[Self.indexTip].position).length
    }

    public var pinchPoint: SpatialVector? {
        guard has(Self.thumbTip), has(Self.indexTip) else { return nil }
        return (poses[Self.thumbTip].position + poses[Self.indexTip].position) * 0.5
    }

    public var indexStraightness: Double? {
        let chain = [Self.indexMetacarpal, Self.indexProximal, Self.indexIntermediate, Self.indexDistal, Self.indexTip]
        guard chain.allSatisfy(has) else { return nil }
        var along = 0.0
        for i in 1..<chain.count { along += (poses[chain[i]].position - poses[chain[i - 1]].position).length }
        guard along > 1e-6 else { return nil }
        return (poses[Self.indexTip].position - poses[Self.indexMetacarpal].position).length / along
    }
}

public struct XRController: Equatable, Sendable, Codable {
    public var aim: SpatialPose?
    public var grip: SpatialPose?
    public var trigger: Double = 0
    public var squeeze: Double = 0
    public var stickX: Double = 0, stickY: Double = 0
    public var stickClick = false
    public var lowerButton = false
    public var upperButton = false

    public init(aim: SpatialPose? = nil, grip: SpatialPose? = nil, trigger: Double = 0, squeeze: Double = 0, stickX: Double = 0, stickY: Double = 0,
                stickClick: Bool = false, lowerButton: Bool = false, upperButton: Bool = false) {
        (self.aim, self.grip, self.trigger, self.squeeze) = (aim, grip, trigger, squeeze)
        (self.stickX, self.stickY, self.stickClick, self.lowerButton, self.upperButton) = (stickX, stickY, stickClick, lowerButton, upperButton)
    }
}

public struct XRTrackingSample: Equatable, Sendable, Codable {
    public var time: Double
    public var head: SpatialPose
    public var leftEye: SpatialPose
    public var rightEye: SpatialPose
    public var gaze: SpatialPose?
    public var hands: [XRHandJoints?]
    public var controllers: [XRController?]
    public var recenter = false

    public init(time: Double, head: SpatialPose, leftEye: SpatialPose? = nil, rightEye: SpatialPose? = nil, gaze: SpatialPose? = nil,
                hands: [XRHandJoints?] = [nil, nil], controllers: [XRController?] = [nil, nil], recenter: Bool = false) {
        self.time = time
        self.head = head
        self.leftEye = leftEye ?? SpatialPose(position: head.transform(point: SpatialVector(-0.0315, 0, 0)), rotation: head.rotation)
        self.rightEye = rightEye ?? SpatialPose(position: head.transform(point: SpatialVector(0.0315, 0, 0)), rotation: head.rotation)
        (self.gaze, self.hands, self.controllers, self.recenter) = (gaze, hands, controllers, recenter)
    }
}

public struct XRInputOutput: Equatable, Sendable {
    public var views: XRViews
    public var selection: SpatialSelection
    public var crown: Bool?
    public var immersion: Double?
    public var recentred = false
}

public struct XRInputMapper: Sendable {
    public enum Pointer: String, Sendable {
        case auto, eyes, controller, head
    }

    public var pointer: Pointer
    public var stereo: Bool
    public var palmOrientation = false
    public var immersionRate = 0.5
    public private(set) var lastGaze: SpatialPose?
    public private(set) var anchor: XRStageAnchor?
    public private(set) var immersion = 0.0
    private var pinch = [XRPinchGate(), XRPinchGate()]
    private var trigger = [XRHysteresis.trigger(), XRHysteresis.trigger()]
    private var pointing = [XRHysteresis.pointing(), XRHysteresis.pointing()]
    private var crownDown = false
    private var lastTime: Double?
    private var sequence: UInt32 = 0
    private var immersionSent: Double?
    private var stickRecentre = false
    public var gazeSettings = XRGazeSettings() {
        didSet { gazeFilter.settings = gazeSettings }
    }
    public var filterGaze: Bool {
        get { gazeSettings.filter != .raw }
        set { gazeSettings.filter = newValue ? .fixation : .raw }
    }
    private var gazeFilter = XRGazeFilter()
    private var lastRawGaze: (yaw: Double, pitch: Double, time: Double)?
    private var inSaccade = false
    private var heldGaze: (pose: SpatialPose, since: Double)?
    private var lastRay: SpatialVector?
    private var lastCell: (Int, Int)?
    private var lastStatSaccade: Double?
    public private(set) var gazeStats = XRGazeStats()
    public private(set) var gazeHeld = false, rayFrozen = false
    public private(set) var saccadeNow = false

    public var pinchSlop = 0.012
    public var handHoldSeconds = 0.2
    public var poke = true
    public var pinchOn = 0.020 { didSet { pinch[0].on = pinchOn; pinch[1].on = pinchOn } }
    public var pinchOff = 0.035 { didSet { pinch[0].off = pinchOff; pinch[1].off = pinchOff } }
    private var frozenRay: (SpatialVector, SpatialVector)?
    private var wasPinching = false
    private var pinchStart: [(position: SpatialVector, time: Double)?] = [nil, nil]
    private var lastHand: [(hand: SpatialHand, time: Double)?] = [nil, nil]
    private var pinchWasOn = [false, false]
    private var pinchBegan: [Double?] = [nil, nil]
    private var pinchEvents: [XRPinchEvent] = []
    public private(set) var pinchCount = 0, handHeldFrames = 0, shortPinches = 0
    public var nearMisses: Int { pinch[0].nearMisses + pinch[1].nearMisses }
    public private(set) var closestApproaches: [Double] = []

    public mutating func takePinchEvents() -> [XRPinchEvent] {
        defer { pinchEvents.removeAll() }
        return pinchEvents
    }

    public var handsDescription: String {
        let sorted = closestApproaches.sorted()
        let p50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2] * 100, p90 = sorted.isEmpty ? 0 : sorted[sorted.count * 9 / 10] * 100
        return String(format: "pinches %d (%d under 60 ms), near misses %d; fingers came to p50 %.1f / p90 %.1f cm (on under %.1f, off over %.1f); a lost hand held for %d frames",
                      pinchCount, shortPinches, nearMisses, p50, p90, pinchOn * 100, pinchOff * 100, handHeldFrames)
    }

    mutating func filteredGaze(_ s: XRTrackingSample) -> SpatialPose? {
        saccadeNow = false
        gazeHeld = false
        guard let g = s.gaze else {
            gazeStats.dropouts += 1
            lastRawGaze = nil
            if let h = heldGaze, s.time - h.since <= gazeSettings.holdSeconds {
                gazeStats.heldFrames += 1
                gazeStats.longestDropout = max(gazeStats.longestDropout, s.time - h.since)
                gazeHeld = true
                return h.pose
            }
            if let h = heldGaze { gazeStats.longestDropout = max(gazeStats.longestDropout, s.time - h.since) }
            heldGaze = nil
            gazeFilter.reset()
            return nil
        }
        gazeStats.samples += 1
        let d = s.head.rotation.conjugate.rotate(g.forward)
        let yaw = atan2(-d.x, -d.z) * 180 / .pi, pitch = asin(max(-1, min(1, d.y))) * 180 / .pi
        var fixating = false
        if let l = lastRawGaze, s.time > l.time {
            let step = ((yaw - l.yaw) * (yaw - l.yaw) + (pitch - l.pitch) * (pitch - l.pitch)).squareRoot()
            let perFrame = step * (1.0 / 90) / max(1e-4, s.time - l.time)
            if perFrame > 3 {
                if !inSaccade { gazeStats.saccades += 1; saccadeNow = true; lastStatSaccade = s.time }
                inSaccade = true
            } else if perFrame < 1.5 {
                inSaccade = false
                fixating = true
                gazeStats.fixationSamples += 1
                gazeStats.rawStepSq += step * step
            }
        }
        lastRawGaze = (yaw, pitch, s.time)
        let sample = gazeFilter.corrected(g.forward, head: s.head.rotation)
        let direction = gazeFilter.update(g.forward, head: s.head.rotation, time: s.time)
        let behind = xrAngleDegrees(sample, direction)
        if !inSaccade { gazeStats.residualSq += behind * behind }
        if fixating {
            let since = lastStatSaccade.map { s.time - $0 } ?? 1
            let band = since < 0.1 ? 0 : since < 0.3 ? 1 : 2
            gazeStats.lagSq[band] += behind * behind
            gazeStats.lagSamples[band] += 1
            if band == 2, let r = lastRay {
                let step = xrAngleDegrees(r, direction)
                gazeStats.rayStepSq += step * step
                gazeStats.raySteps += 1
            }
        }
        lastRay = direction
        let (ry, rp) = xrYawPitch(direction)
        let cell = (Int((ry * 180 / .pi / 3).rounded()), Int((rp * 180 / .pi / 3).rounded()))
        if let c = lastCell, c != cell { gazeStats.cellChanges += 1 }
        lastCell = cell
        let pose = SpatialPose(position: g.position, rotation: SpatialQuaternion(yaw: ry, pitch: rp).normalized)
        heldGaze = (pose, s.time)
        return pose
    }

    private func rewound(_ pose: SpatialPose?, at time: Double) -> (pose: SpatialPose, milliseconds: Int)? {
        guard let pose, gazeSettings.pinchRewindSeconds > 0, gazeSettings.filter == .fixation, let at = gazeFilter.lastSaccadeAt,
              time - at <= gazeSettings.pinchRewindSeconds, let f = gazeFilter.previousFixation, f.lasted >= gazeSettings.rewindMinimumFixation else { return nil }
        let (y, p) = xrYawPitch(f.direction)
        return (SpatialPose(position: pose.position, rotation: SpatialQuaternion(yaw: y, pitch: p).normalized), Int((time - at) * 1000))
    }

    public func headSpaceGaze(_ s: XRTrackingSample) -> SpatialVector? { s.gaze.map { s.head.rotation.conjugate.rotate($0.forward) } }

    public init(pointer: Pointer = .auto, stereo: Bool = true, immersion: Double = 0) {
        self.pointer = pointer
        self.stereo = stereo
        self.immersion = immersion
    }

    public mutating func anchor(at head: SpatialPose) { anchor = XRStageAnchor(head: head) }

    public mutating func setImmersion(_ a: Double) {
        immersion = min(max(a, 0), 1)
        immersionSent = immersion
    }

    public mutating func map(_ s: XRTrackingSample) -> XRInputOutput {
        var recentred = false
        let rightStickClick = s.controllers.count > 1 && (s.controllers[1]?.stickClick ?? false)
        if anchor == nil || s.recenter || (rightStickClick && !stickRecentre) {
            anchor(at: s.head)
            recentred = anchor != nil && (s.recenter || rightStickClick)
        }
        stickRecentre = rightStickClick
        let a = anchor!
        let dt = lastTime.map { max(0, min(0.1, s.time - $0)) } ?? 0
        lastTime = s.time
        sequence &+= 1
        let head = a.toStage(s.head)
        let views = XRViews(sequence: sequence, stereo: stereo, head: head, left: a.toStage(s.leftEye), right: a.toStage(s.rightEye))

        var hands: [SpatialHand] = []
        for i in 0..<2 {
            let rest = i == 0 ? SpatialInteraction.leftRest : SpatialInteraction.rightRest
            var h = SpatialHand(pinching: false, allowDirect: false, position: head.transform(point: rest), rotation: head.rotation)
            if i < s.hands.count, let j = s.hands[i], let point = j.pinchPoint, let d = j.pinchDistance {
                let pinched = pinch[i].update(d, time: s.time)
                let straight = j.indexStraightness ?? 0
                let poke = self.poke && !pinched && pointing[i].update(straight)
                if pinched { pointing[i].reset() }
                let at = poke ? j.poses[XRHandJoints.indexTip].position : point
                h.pinching = pinched
                h.allowDirect = poke
                h.position = a.toStage(point: at)
                if palmOrientation, j.has(XRHandJoints.palm) { h.rotation = a.toStage(j.poses[XRHandJoints.palm]).rotation }
                trigger[i].reset()
            } else if i < s.controllers.count, let c = s.controllers[i], let place = c.grip ?? c.aim {
                h.pinching = trigger[i].update(c.trigger)
                h.position = a.toStage(point: place.position)
                if palmOrientation { h.rotation = a.toStage(place).rotation }
                pinch[i].reset()
                pointing[i].reset()
            } else if let l = lastHand[i], s.time - l.time <= handHoldSeconds {
                h = l.hand
                handHeldFrames += 1
            } else {
                pinch[i].reset()
                trigger[i].reset()
                pointing[i].reset()
            }
            let held = i < s.hands.count && (s.hands[i] == nil || s.hands[i]?.pinchDistance == nil)
                && !(i < s.controllers.count && s.controllers[i] != nil) && lastHand[i].map { s.time - $0.time <= handHoldSeconds } == true
            if h.pinching, !held {
                let start = pinchStart[i] ?? (h.position, s.time)
                pinchStart[i] = start
                let moved = h.position - start.position
                let far = moved.length
                h.position = far <= pinchSlop ? start.position : start.position + moved * (1 - pinchSlop / far)
            } else if !h.pinching {
                pinchStart[i] = nil
            }
            if !held {
                let tracked = i < s.hands.count && s.hands[i]?.pinchDistance != nil
                lastHand[i] = tracked || (i < s.controllers.count && s.controllers[i] != nil) ? (h, s.time) : nil
            }
            hands.append(h)
        }

        let controllerAim = s.controllers.indices.reversed().compactMap { i -> SpatialPose? in
            s.controllers[i]?.aim
        }.first
        func rayOf(_ p: SpatialPose) -> (SpatialVector, SpatialVector) {
            let sp = a.toStage(p)
            return (sp.position, sp.forward)
        }
        var gaze = filteredGaze(s)
        let usesGaze: Bool
        switch pointer {
        case .eyes, .auto: usesGaze = gaze != nil
        case .controller, .head: usesGaze = false
        }

        let pinching = hands.contains { $0.pinching }
        var gazeState = XRPinchEvent.Gaze.noGaze
        if gazeHeld, let h = heldGaze { gazeState = .heldThroughDropout(milliseconds: Int((s.time - h.since) * 1000)) }
        else if gaze != nil { gazeState = .fixating(milliseconds: Int((gazeFilter.fixationAge(at: s.time) ?? 0) * 1000)) }
        if pinching && !wasPinching, usesGaze, let r = rewound(gaze, at: s.time) {
            gaze = r.pose
            gazeStats.rewinds += 1
            gazeState = .rewound(milliseconds: r.milliseconds)
        }
        for i in 0..<2 where hands[i].pinching != pinchWasOn[i] {
            if hands[i].pinching {
                pinchCount += 1
                pinchEvents.append(XRPinchEvent(began: true, hand: i, time: s.time, gaze: gazeState))
                pinchBegan[i] = s.time
            } else {
                let lasted = pinchBegan[i].map { s.time - $0 }
                if let lasted, lasted < 0.06 { shortPinches += 1 }
                let closest = pinch[i].takeClosest()
                if let closest, closestApproaches.count < 4096 { closestApproaches.append(closest) }
                pinchEvents.append(XRPinchEvent(began: false, hand: i, time: s.time, gaze: gazeState, duration: lasted, closestCentimetres: closest.map { $0 * 100 }))
            }
            pinchWasOn[i] = hands[i].pinching
        }
        let ray: (SpatialVector, SpatialVector)
        rayFrozen = false
        if gazeSettings.freezeDuringPinch, usesGaze || frozenRay != nil, pinching || wasPinching {
            let r = frozenRay ?? gaze.map(rayOf) ?? rayOf(s.head)
            ray = r
            frozenRay = pinching ? r : nil
            rayFrozen = true
            gazeStats.frozenFrames += 1
        } else {
            frozenRay = nil
            switch pointer {
            case .eyes: ray = gaze.map(rayOf) ?? rayOf(s.head)
            case .controller: ray = controllerAim.map(rayOf) ?? rayOf(s.head)
            case .head: ray = rayOf(s.head)
            case .auto: ray = gaze.map(rayOf) ?? controllerAim.map(rayOf) ?? rayOf(s.head)
            }
        }
        wasPinching = pinching
        lastGaze = gaze
        let selection = SpatialSelection(rayOrigin: ray.0, rayDirection: ray.1, left: hands[0], right: hands[1])

        let crownPressed = s.controllers.contains { $0?.lowerButton ?? false }
        var crown: Bool?
        if crownPressed != crownDown { crown = crownPressed; crownDown = crownPressed }

        let stick = s.controllers.compactMap { $0?.stickY }.max { abs($0) < abs($1) } ?? 0
        var sendImmersion: Double?
        if abs(stick) > 0.2, dt > 0 {
            immersion = min(max(immersion + stick * immersionRate * dt, 0), 1)
            if immersionSent.map({ abs($0 - immersion) >= 0.01 }) ?? true {
                sendImmersion = immersion
                immersionSent = immersion
            }
        }
        return XRInputOutput(views: views, selection: selection, crown: crown, immersion: sendImmersion, recentred: recentred)
    }
}

public enum XRSampleScript {
    public static func encode(_ s: XRTrackingSample, keepGaze: Bool = false) -> String {
        var c = s
        if !keepGaze { c.gaze = nil }
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return String(decoding: (try? e.encode(c)) ?? Data("{}".utf8), as: UTF8.self)
    }

    public static func decode(_ text: String) throws -> [XRTrackingSample] {
        let d = JSONDecoder()
        return try text.split(whereSeparator: \.isNewline).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { return nil }
            return try d.decode(XRTrackingSample.self, from: Data(t.utf8))
        }
    }
}

public enum XRPictureSignature {
    public static func of(_ base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        guard width > 0, height > 0 else { return h }
        for gy in 0..<36 {
            let y = min(height - 1, (2 * gy + 1) * height / 72)
            let row = base.advanced(by: y * bytesPerRow)
            for gx in 0..<64 {
                let x = min(width - 1, (2 * gx + 1) * width / 128)
                let v = row.loadUnaligned(fromByteOffset: x * 4, as: UInt32.self)
                h = (h ^ UInt64(v)) &* 0x100_0000_01b3
            }
        }
        return h
    }
}
