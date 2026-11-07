import Foundation

public enum TopBounce {
    public static let omega = 12.6
    public static let riseOmega = 15.0
    public static let riseGain = 0.78
    public static let restThreshold = 0.25
    public static let maximumShare = 0.25

    public static func overscroll(velocity: Double, at t: Double) -> Double {
        overscroll(from: 0, velocity: velocity, at: t)
    }

    public static func overscroll(from start: Double, velocity: Double, at t: Double) -> Double {
        let x0 = max(0, start)
        guard t > 0 else { return x0 }
        let t1 = peakTime(from: x0, velocity: velocity)
        if t <= t1 { return rise(from: x0, velocity: velocity, at: t) }
        let p = rise(from: x0, velocity: velocity, at: t1)
        let r = t - t1
        return p * (1 + omega * r) * exp(-omega * r)
    }

    private static func rise(from x0: Double, velocity: Double, at t: Double) -> Double {
        (x0 + (riseGain * max(0, velocity) + riseOmega * x0) * t) * exp(-riseOmega * t)
    }

    public static var peakTime: Double { 1 / riseOmega }

    public static func peakTime(from start: Double, velocity: Double) -> Double {
        let a = max(0, start), b = riseGain * max(0, velocity) + riseOmega * a
        guard b > 0 else { return 0 }
        return max(0, 1 / riseOmega - a / b)
    }

    public static func peak(velocity: Double) -> Double { riseGain * max(0, velocity) / (riseOmega * M_E) }

    public static func velocity(forPeak peak: Double) -> Double { max(0, peak) * riseOmega * M_E / riseGain }

    public static func effectiveVelocity(_ velocity: Double, visibleHeight: Double) -> Double {
        let cap = visibleHeight > 0 ? self.velocity(forPeak: visibleHeight * maximumShare) : .infinity
        return min(max(0, velocity), cap)
    }

    public static func isAtRest(velocity: Double, at t: Double) -> Bool {
        isAtRest(from: 0, velocity: velocity, at: t)
    }

    public static func isAtRest(from start: Double, velocity: Double, at t: Double) -> Bool {
        t >= peakTime(from: start, velocity: velocity) && overscroll(from: start, velocity: velocity, at: t) < restThreshold
    }

    public static func duration(velocity: Double) -> Double {
        guard velocity > 0 else { return 0 }
        var t = peakTime
        while !isAtRest(velocity: velocity, at: t) { t += 0.001 }
        return t
    }

    public struct VelocityTracker: Sendable {
        public private(set) var velocity = 0.0
        public private(set) var hasSample = false
        private var lastTime: Double?

        public init() {}

        public mutating func reset() {
            velocity = 0
            hasSample = false
            lastTime = nil
        }

        public mutating func add(_ points: Double, at time: Double) {
            guard points != 0 else { return }
            defer { lastTime = time }
            guard let last = lastTime else { return }
            let dt = time - last
            guard dt > 0.0005, dt < 0.1 else { return }
            let v = points / dt
            velocity = hasSample ? 0.3 * velocity + 0.7 * v : v
            hasSample = true
        }
    }
}
