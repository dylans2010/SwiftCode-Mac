import Foundation

public struct XRCameraHold: Sendable {
    public var bandMetres = 0.015, bandRadians = 1.5 * Double.pi / 180
    public var restMetres = 0.003, restRadians = 0.3 * Double.pi / 180
    public var restSeconds = 0.15
    private var held: SpatialPose?
    private var reference: (pose: SpatialPose, time: Double)?

    public init() {}

    public static func differs(_ a: SpatialPose, _ b: SpatialPose, metres: Double, radians: Double) -> Bool {
        if (a.position - b.position).length > metres { return true }
        let q = (a.rotation.conjugate * b.rotation).normalized
        return 2 * acos(min(1, abs(q.w))) > radians
    }

    public var holding: Bool { held != nil }

    public mutating func reset() { held = nil; reference = nil }

    public mutating func apply(_ head: SpatialPose, time: Double) -> SpatialPose {
        if let h = held {
            if !Self.differs(head, h, metres: bandMetres, radians: bandRadians) { return h }
            held = nil
            reference = (head, time)
            return head
        }
        guard let r = reference else {
            held = head
            return head
        }
        if Self.differs(head, r.pose, metres: restMetres, radians: restRadians) {
            reference = (head, time)
        } else if time - r.time >= restSeconds {
            held = head
            reference = nil
        }
        return head
    }
}

public struct XRSweep: Sendable {
    public let stops: [SpatialQuaternion]
    public private(set) var index = 0
    public var current: SpatialQuaternion? { index < stops.count ? stops[index] : nil }
    public var finished: Bool { index >= stops.count }

    public init(fov: XRFieldOfView) { stops = Self.stops(fov: fov) }

    public mutating func advance() { index += 1 }

    public static func stops(fov: XRFieldOfView, marginDegrees: Double = 12) -> [SpatialQuaternion] {
        let t = fov.tangents
        let halfWide = atan(min(abs(t.left), abs(t.right))) * 180 / .pi
        let halfTall = atan(min(abs(t.up), abs(t.down))) * 180 / .pi
        let rowStep = max(20, 2 * halfTall - marginDegrees)
        var rows = [0.0]
        var p = rowStep
        while p - rowStep + halfTall < 90 - min(halfWide, halfTall) {
            rows += [p, -p]
            p += rowStep
        }
        let n = max(4, Int((360 / (2 * halfWide - marginDegrees)).rounded(.up)))
        var out: [SpatialQuaternion] = []
        for pitch in rows {
            let yaws = (0..<n).map { i -> Double in
                let k = Double((i + 1) / 2) * 360 / Double(n)
                return i % 2 == 1 ? k : -k
            }
            for yaw in yaws { out.append(SpatialQuaternion(yaw: yaw * .pi / 180, pitch: pitch * .pi / 180)) }
        }
        out.append(SpatialQuaternion(yaw: 0, pitch: 89 * .pi / 180))
        out.append(SpatialQuaternion(yaw: 0, pitch: -89 * .pi / 180))
        let degree = Double.pi / 180
        for j in 0..<36 {
            for i in 0..<72 {
                let az = Double(i) * 5 * degree, el = (Double(j) * 5 - 87.5) * degree
                let d = SpatialVector(cos(el) * sin(az), sin(el), cos(el) * cos(az))
                if !out.contains(where: { sees($0, d, t) }) {
                    out.append(SpatialQuaternion(yaw: atan2(-d.x, -d.z), pitch: el))
                }
            }
        }
        return out
    }

    public static func sees(_ r: SpatialQuaternion, _ d: SpatialVector, _ t: (left: Double, right: Double, up: Double, down: Double)) -> Bool {
        let l = r.conjugate.rotate(d)
        guard l.z < 0 else { return false }
        let x = l.x / -l.z, y = l.y / -l.z
        return x > t.left * 0.97 && x < t.right * 0.97 && y < t.up * 0.97 && y > t.down * 0.97
    }
}

public struct XRFinalPictureRule: Sendable {
    public var holdNanoseconds: UInt64
    public var settleNanoseconds: UInt64
    public var nothingNewNanoseconds: UInt64 = 1_500_000_000
    public init(holdNanoseconds: UInt64, settleNanoseconds: UInt64) { (self.holdNanoseconds, self.settleNanoseconds) = (holdNanoseconds, settleNanoseconds) }

    public func isFinal(uploadedAt: UInt64, commandedAt: UInt64, now: UInt64, finalFor: UInt64, sweeping: Bool) -> Bool {
        finalFor == commandedAt
            || uploadedAt >= commandedAt + holdNanoseconds
            || (uploadedAt >= commandedAt && now >= uploadedAt + settleNanoseconds + (sweeping ? 200_000_000 : 0))
            || (!sweeping && now >= commandedAt + nothingNewNanoseconds)
    }
}

public struct XRFreshOnTopRule: Sendable {
    public var afterNanoseconds: UInt64
    public init(afterNanoseconds: UInt64) { self.afterNanoseconds = afterNanoseconds }
    public func isOnTop(now: UInt64, commandedAt: UInt64, oneView: Bool, sweeping: Bool) -> Bool {
        afterNanoseconds > 0 && oneView && !sweeping && now >= commandedAt + afterNanoseconds
    }
}

public struct XRCameraSpeed: Sendable {
    public var windowSeconds = 0.1
    public private(set) var degreesPerSecond = 0.0, metresPerSecond = 0.0
    private var reference: (pose: SpatialPose, time: Double)?

    public init() {}

    public mutating func update(_ pose: SpatialPose, time: Double) {
        guard let r = reference else { reference = (pose, time); return }
        let dt = time - r.time
        guard dt >= windowSeconds else { return }
        let q = (r.pose.rotation.conjugate * pose.rotation).normalized
        degreesPerSecond = 2 * acos(min(1, abs(q.w))) * 180 / .pi / dt
        metresPerSecond = (pose.position - r.pose.position).length / dt
        reference = (pose, time)
    }

    public func isSlow(limitDegrees limit: Double) -> Bool { limit > 0 && degreesPerSecond <= limit && metresPerSecond <= limit / 100 }
}
