import Foundation

public struct SpatialVector: Equatable, Sendable, Codable, CustomStringConvertible {
    public var x: Double, y: Double, z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) { (self.x, self.y, self.z) = (x, y, z) }

    public static let zero = SpatialVector(0, 0, 0)

    public static func + (a: SpatialVector, b: SpatialVector) -> SpatialVector { SpatialVector(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: SpatialVector, b: SpatialVector) -> SpatialVector { SpatialVector(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: SpatialVector, s: Double) -> SpatialVector { SpatialVector(a.x * s, a.y * s, a.z * s) }
    public static prefix func - (a: SpatialVector) -> SpatialVector { SpatialVector(-a.x, -a.y, -a.z) }

    public func dot(_ b: SpatialVector) -> Double { x * b.x + y * b.y + z * b.z }
    public func cross(_ b: SpatialVector) -> SpatialVector {
        SpatialVector(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }
    public var length: Double { dot(self).squareRoot() }
    public var normalized: SpatialVector { length > 0 ? self * (1 / length) : self }

    public var description: String { String(format: "(%.4f, %.4f, %.4f)", x, y, z) }
}

public struct SpatialQuaternion: Equatable, Sendable, Codable, CustomStringConvertible {
    public var x: Double, y: Double, z: Double, w: Double

    public init(x: Double, y: Double, z: Double, w: Double) { (self.x, self.y, self.z, self.w) = (x, y, z, w) }

    public static let identity = SpatialQuaternion(x: 0, y: 0, z: 0, w: 1)

    public init(axis: SpatialVector, radians: Double) {
        let a = axis.normalized, s = sin(radians / 2)
        self.init(x: a.x * s, y: a.y * s, z: a.z * s, w: cos(radians / 2))
    }

    public init(yaw: Double, pitch: Double) {
        self = SpatialQuaternion(axis: SpatialVector(0, 1, 0), radians: yaw) * SpatialQuaternion(axis: SpatialVector(1, 0, 0), radians: pitch)
    }

    public static func * (a: SpatialQuaternion, b: SpatialQuaternion) -> SpatialQuaternion {
        SpatialQuaternion(x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
                          y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
                          z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
                          w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
    }

    public var conjugate: SpatialQuaternion { SpatialQuaternion(x: -x, y: -y, z: -z, w: w) }

    public var normalized: SpatialQuaternion {
        let n = (x * x + y * y + z * z + w * w).squareRoot()
        return n > 0 ? SpatialQuaternion(x: x / n, y: y / n, z: z / n, w: w / n) : .identity
    }

    public func rotate(_ v: SpatialVector) -> SpatialVector {
        let u = SpatialVector(x, y, z)
        let t = u.cross(v) * 2
        return v + t * w + u.cross(t)
    }

    public var rows: [[Double]] {
        [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    }

    public var description: String { String(format: "(x %.4f, y %.4f, z %.4f, w %.4f)", x, y, z, w) }
}

public struct SpatialPose: Equatable, Sendable, Codable, CustomStringConvertible {
    public var position: SpatialVector
    public var rotation: SpatialQuaternion

    public init(position: SpatialVector = .zero, rotation: SpatialQuaternion = .identity) {
        (self.position, self.rotation) = (position, rotation)
    }

    public static let identity = SpatialPose()

    public func transform(point p: SpatialVector) -> SpatialVector { position + rotation.rotate(p) }
    public func transform(direction d: SpatialVector) -> SpatialVector { rotation.rotate(d) }

    public var columnMajor: [Float] {
        let r = rotation.normalized.rows
        var m = [Float](repeating: 0, count: 16)
        for c in 0..<3 { for row in 0..<3 { m[c * 4 + row] = Float(r[row][c]) } }
        m[12] = Float(position.x)
        m[13] = Float(position.y)
        m[14] = Float(position.z)
        m[15] = 1
        return m
    }

    public var matrixBytes: [UInt8] {
        var b: [UInt8] = []
        b.reserveCapacity(64)
        for v in columnMajor { withUnsafeBytes(of: v.bitPattern.littleEndian) { b += $0 } }
        return b
    }

    public init?(matrixBytes b: [UInt8]) {
        guard b.count == 64 else { return nil }
        var m = [Double](repeating: 0, count: 16)
        for i in 0..<16 {
            var bits: UInt32 = 0
            for k in 0..<4 { bits |= UInt32(b[i * 4 + k]) << (8 * UInt32(k)) }
            m[i] = Double(Float(bitPattern: bits))
        }
        func r(_ row: Int, _ col: Int) -> Double { m[col * 4 + row] }
        let trace = r(0, 0) + r(1, 1) + r(2, 2)
        var q: SpatialQuaternion
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            q = SpatialQuaternion(x: (r(2, 1) - r(1, 2)) / s, y: (r(0, 2) - r(2, 0)) / s, z: (r(1, 0) - r(0, 1)) / s, w: s / 4)
        } else if r(0, 0) > r(1, 1) && r(0, 0) > r(2, 2) {
            let s = (1 + r(0, 0) - r(1, 1) - r(2, 2)).squareRoot() * 2
            q = SpatialQuaternion(x: s / 4, y: (r(0, 1) + r(1, 0)) / s, z: (r(0, 2) + r(2, 0)) / s, w: (r(2, 1) - r(1, 2)) / s)
        } else if r(1, 1) > r(2, 2) {
            let s = (1 + r(1, 1) - r(0, 0) - r(2, 2)).squareRoot() * 2
            q = SpatialQuaternion(x: (r(0, 1) + r(1, 0)) / s, y: s / 4, z: (r(1, 2) + r(2, 1)) / s, w: (r(0, 2) - r(2, 0)) / s)
        } else {
            let s = (1 + r(2, 2) - r(0, 0) - r(1, 1)).squareRoot() * 2
            q = SpatialQuaternion(x: (r(0, 2) + r(2, 0)) / s, y: (r(1, 2) + r(2, 1)) / s, z: s / 4, w: (r(1, 0) - r(0, 1)) / s)
        }
        if q.w < 0 { q = SpatialQuaternion(x: -q.x, y: -q.y, z: -q.z, w: -q.w) }
        self.init(position: SpatialVector(m[12], m[13], m[14]), rotation: q.normalized)
    }

    public var forward: SpatialVector { rotation.rotate(SpatialVector(0, 0, -1)) }

    public var description: String { "position \(position) rotation \(rotation)" }
}

public struct SpatialHand: Equatable, Sendable, Codable {
    public var pinching: Bool
    public var allowDirect: Bool
    public var position: SpatialVector
    public var rotation: SpatialQuaternion

    public init(pinching: Bool = false, allowDirect: Bool = false, position: SpatialVector = .zero, rotation: SpatialQuaternion = .identity) {
        (self.pinching, self.allowDirect, self.position, self.rotation) = (pinching, allowDirect, position, rotation)
    }
}

public struct SpatialSelection: Equatable, Sendable, Codable {
    public var rayOrigin: SpatialVector
    public var rayDirection: SpatialVector
    public var left: SpatialHand?
    public var right: SpatialHand?

    public init(rayOrigin: SpatialVector, rayDirection: SpatialVector, left: SpatialHand? = nil, right: SpatialHand? = nil) {
        (self.rayOrigin, self.rayDirection, self.left, self.right) = (rayOrigin, rayDirection, left, right)
    }

    public var hasHands: Bool { left != nil && right != nil }
    public var anyPinch: Bool { (left?.pinching ?? false) || (right?.pinching ?? false) }
}

public enum SpatialProjection {
    public static func viewDirection(x: Double, y: Double, width: Double, height: Double) -> SpatialVector {
        let f = width / 2
        return SpatialVector((x - width / 2) / f, -(y - height / 2) / f, -1)
    }

    public static func viewPoint(direction d: SpatialVector, width: Double, height: Double) -> (x: Double, y: Double)? {
        guard d.z < 0 else { return nil }
        let f = width / 2
        return (width / 2 + f * d.x / -d.z, height / 2 - f * d.y / -d.z)
    }
}

public struct SpatialCamera: Equatable, Sendable {
    public var position = SpatialVector.zero
    public var yaw = 0.0
    public var pitch = 0.0

    public init(position: SpatialVector = .zero, yaw: Double = 0, pitch: Double = 0) {
        self.position = position
        self.yaw = yaw
        self.pitch = Self.clampPitch(pitch)
    }

    static func clampPitch(_ p: Double) -> Double { min(max(p, -89 * .pi / 180), 89 * .pi / 180) }

    public var pose: SpatialPose { SpatialPose(position: position, rotation: SpatialQuaternion(yaw: yaw, pitch: pitch)) }

    public mutating func move(forward: Double = 0, right: Double = 0, up: Double = 0) {
        let f = SpatialVector(-sin(yaw), 0, -cos(yaw)), r = SpatialVector(cos(yaw), 0, -sin(yaw))
        position = position + f * forward + r * right + SpatialVector(0, up, 0)
    }

    public mutating func turn(yaw dy: Double, pitch dp: Double) {
        yaw = (yaw + dy).truncatingRemainder(dividingBy: 2 * .pi)
        pitch = Self.clampPitch(pitch + dp)
    }

    public mutating func reset() { self = SpatialCamera() }

    public init(pose: SpatialPose) {
        let f = pose.forward
        self.init(position: pose.position, yaw: atan2(-f.x, -f.z), pitch: asin(max(-1, min(1, f.y))))
    }
}

public struct SpatialInteraction: Equatable, Sendable {
    public var width: Double, height: Double
    public var camera = SpatialCamera()
    public var metresPerPoint = 1.0 / 700
    public static let leftRest = SpatialVector(-0.15, -0.35, -0.4)
    public static let rightRest = SpatialVector(0.15, -0.35, -0.4)
    public static let keyStep = 0.05
    public static let lookRadiansPerPoint = 0.2 * .pi / 180

    public enum Mode: Equatable, Sendable {
        case idle
        case pinch(start: Point, gaze: Point, depth: Double)
        case twoHands(start: Point, gaze: Point)
    }

    public struct Point: Equatable, Sendable {
        public var x: Double, y: Double
        public init(_ x: Double, _ y: Double) { (self.x, self.y) = (x, y) }
    }

    public private(set) var mode = Mode.idle
    public private(set) var pointer = Point(0, 0)
    private var handOffset = SpatialVector.zero

    public init(width: Double = 1920, height: Double = 1080) {
        (self.width, self.height) = (width, height)
        pointer = Point(width / 2, height / 2)
    }

    public var isPinching: Bool { mode != .idle }

    public func ray(x: Double, y: Double) -> (origin: SpatialVector, direction: SpatialVector) {
        let pose = camera.pose
        return (pose.position, pose.transform(direction: SpatialProjection.viewDirection(x: x, y: y, width: width, height: height)))
    }

    func clamp(_ x: Double, _ y: Double) -> Point { Point(min(max(x, 0), width), min(max(y, 0), height)) }

    func hand(_ p: SpatialVector, pinching: Bool) -> SpatialHand {
        let pose = camera.pose
        return SpatialHand(pinching: pinching, allowDirect: false, position: pose.transform(point: p), rotation: pose.rotation)
    }

    func selection(gaze: Point, left: SpatialHand?, right: SpatialHand?) -> SpatialSelection {
        let r = ray(x: gaze.x, y: gaze.y)
        return SpatialSelection(rayOrigin: r.origin, rayDirection: r.direction, left: left, right: right)
    }

    public mutating func hover(x: Double, y: Double) -> SpatialSelection {
        if mode != .idle { return drag(x: x, y: y) }
        pointer = clamp(x, y)
        return selection(gaze: pointer, left: nil, right: nil)
    }

    public var gazeSelection: SpatialSelection { selection(gaze: pointer, left: nil, right: nil) }

    public mutating func press(x: Double, y: Double, twoHands: Bool = false) -> SpatialSelection {
        let p = clamp(x, y)
        pointer = p
        if twoHands {
            mode = .twoHands(start: p, gaze: p)
            handOffset = (Self.rightRest - Self.leftRest) * 0.5
        } else {
            mode = .pinch(start: p, gaze: p, depth: 0)
            handOffset = .zero
        }
        return current(pinching: true)
    }

    public mutating func drag(x: Double, y: Double, depth: Bool = false) -> SpatialSelection {
        let p = clamp(x, y)
        switch mode {
        case .idle:
            return hover(x: x, y: y)
        case .pinch(let start, let gaze, var d):
            if depth {
                d += (pointer.y - p.y) * metresPerPoint
                mode = .pinch(start: Point(start.x, start.y + (p.y - pointer.y)), gaze: gaze, depth: d)
            }
            pointer = p
        case .twoHands:
            pointer = p
        }
        return current(pinching: true)
    }

    public mutating func release() -> SpatialSelection? {
        guard mode != .idle else { return nil }
        let s = current(pinching: false)
        mode = .idle
        return s
    }

    func handPositions() -> (left: SpatialVector, right: SpatialVector, gaze: Point) {
        switch mode {
        case .idle:
            return (Self.leftRest, Self.rightRest, pointer)
        case .pinch(let start, let gaze, let depth):
            let d = SpatialVector((pointer.x - start.x) * metresPerPoint, -(pointer.y - start.y) * metresPerPoint, -depth)
            return (Self.leftRest, Self.rightRest + d, gaze)
        case .twoHands(let start, let gaze):
            let centre = (Self.leftRest + Self.rightRest) * 0.5
            let d = SpatialVector((pointer.x - start.x) * metresPerPoint, -(pointer.y - start.y) * metresPerPoint, 0)
            let o = handOffset + d
            return (centre - o, centre + o, gaze)
        }
    }

    func current(pinching: Bool) -> SpatialSelection {
        let h = handPositions()
        let two: Bool = { if case .twoHands = mode { true } else { false } }()
        return selection(gaze: h.gaze, left: hand(h.left, pinching: pinching && two), right: hand(h.right, pinching: pinching))
    }

    public func twoHandOffset(scale: Double, radians: Double) -> (dx: Double, dy: Double) {
        let h = (Self.rightRest.x - Self.leftRest.x) / 2
        let ox = h * scale * cos(radians), oy = h * scale * sin(radians)
        return ((ox - h) / metresPerPoint, -oy / metresPerPoint)
    }

    public var pointerPosition: Point { pointer }

    public mutating func setCamera(_ pose: SpatialPose) { camera = SpatialCamera(pose: pose) }

    public mutating func step(forward: Double = 0, right: Double = 0, up: Double = 0) -> SpatialPose {
        camera.move(forward: forward * Self.keyStep, right: right * Self.keyStep, up: up * Self.keyStep)
        return camera.pose
    }

    public mutating func look(dx: Double, dy: Double) -> SpatialPose {
        camera.turn(yaw: -dx * Self.lookRadiansPerPoint, pitch: -dy * Self.lookRadiansPerPoint)
        return camera.pose
    }

    public mutating func resetCamera() -> SpatialPose {
        camera.reset()
        return camera.pose
    }
}

public enum SpatialCameraKeys {
    public static func direction(usage: UInt16) -> (forward: Double, right: Double, up: Double)? {
        switch usage {
        case 0x1A, 0x52: (1, 0, 0)
        case 0x16, 0x51: (-1, 0, 0)
        case 0x04, 0x50: (0, -1, 0)
        case 0x07, 0x4F: (0, 1, 0)
        case 0x08: (0, 0, 1)
        case 0x14: (0, 0, -1)
        default: nil
        }
    }
}
