import Foundation

public struct Animation: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let base: any CustomAnimation

    public init<A: CustomAnimation>(_ base: A) {
        if let a = base as? Animation { self = a } else { self.base = base }
    }

    public static func == (lhs: Animation, rhs: Animation) -> Bool { AnyHashable(lhs.base) == AnyHashable(rhs.base) }
    public func hash(into hasher: inout Hasher) { hasher.combine(AnyHashable(base)) }

    public var description: String { String(describing: base) }
    public var debugDescription: String { description }

    public func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        base.animate(value: value, time: time, context: &context)
    }

    public func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        base.velocity(value: value, time: time, context: context)
    }

    public func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                                 context: inout AnimationContext<V>) -> Bool {
        base.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }

    package func cycleDuration() -> TimeInterval? {
        if let c = base as? TimingCurveAnimation { return c.duration }
        if let d = base as? DelayAnimation, let inner = d.animation.cycleDuration() { return d.delay + inner }
        if let s = base as? SpeedAnimation, let inner = s.animation.cycleDuration() { return s.speed > 0 ? inner / s.speed : nil }
        var ctx = AnimationContext<Double>()
        var t = 0.0
        let step = 1.0 / 240
        while t < 3600 {
            if animate(value: 1.0, time: t, context: &ctx) == nil { return t }
            t += step
        }
        return nil
    }

    private static let defaultCurveDuration: TimeInterval = 0.35

    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation {
        Animation(TimingCurveAnimation(curve: curve, duration: duration))
    }

    public static func timingCurve(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double,
                                   duration: TimeInterval = 0.35) -> Animation {
        timingCurve(.bezier(startControlPoint: UnitPoint(x: p1x, y: p1y), endControlPoint: UnitPoint(x: p2x, y: p2y)),
                    duration: duration)
    }

    public static var linear: Animation { linear(duration: defaultCurveDuration) }
    public static func linear(duration: TimeInterval) -> Animation { timingCurve(.linear, duration: duration) }
    public static var easeIn: Animation { easeIn(duration: defaultCurveDuration) }
    public static func easeIn(duration: TimeInterval) -> Animation { timingCurve(.easeIn, duration: duration) }
    public static var easeOut: Animation { easeOut(duration: defaultCurveDuration) }
    public static func easeOut(duration: TimeInterval) -> Animation { timingCurve(.easeOut, duration: duration) }
    public static var easeInOut: Animation { easeInOut(duration: defaultCurveDuration) }
    public static func easeInOut(duration: TimeInterval) -> Animation { timingCurve(.easeInOut, duration: duration) }

    public static let `default` = Animation(SpringAnimation(spring: Spring(response: 0.5, dampingRatio: 1)))

    public static func spring(_ spring: Spring, blendDuration: TimeInterval = 0) -> Animation {
        Animation(SpringAnimation(spring: spring, blendDuration: blendDuration))
    }

    public static var spring: Animation { spring(duration: 0.5, bounce: 0) }

    @_disfavoredOverload
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825,
                              blendDuration: TimeInterval = 0) -> Animation {
        spring(Spring(response: response, dampingRatio: dampingFraction), blendDuration: blendDuration)
    }

    public static func spring(duration: TimeInterval = 0.5, bounce: Double = 0, blendDuration: Double = 0) -> Animation {
        spring(Spring(duration: duration, bounce: bounce), blendDuration: blendDuration)
    }

    public static var interactiveSpring: Animation { interactiveSpring(response: 0.15, dampingFraction: 0.85, blendDuration: 0.25) }

    @_disfavoredOverload
    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.85,
                                         blendDuration: TimeInterval = 0.25) -> Animation {
        spring(Spring(response: response, dampingRatio: dampingFraction), blendDuration: blendDuration)
    }

    public static func interactiveSpring(duration: TimeInterval = 0.15, extraBounce: Double = 0,
                                         blendDuration: TimeInterval = 0.25) -> Animation {
        spring(Spring(duration: duration, bounce: 0.15 + extraBounce), blendDuration: blendDuration)
    }

    public static var smooth: Animation { spring(.smooth) }
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
        spring(.smooth(duration: duration, extraBounce: extraBounce))
    }

    public static var snappy: Animation { spring(.snappy) }
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
        spring(.snappy(duration: duration, extraBounce: extraBounce))
    }

    public static var bouncy: Animation { spring(.bouncy) }
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
        spring(.bouncy(duration: duration, extraBounce: extraBounce))
    }

    public static var interpolatingSpring: Animation {
        interpolatingSpring(mass: 1, stiffness: 157.9137, damping: 25.1327)
    }

    public static func interpolatingSpring(mass: Double = 1, stiffness: Double, damping: Double,
                                           initialVelocity: Double = 0) -> Animation {
        Animation(SpringAnimation(spring: Spring(mass: mass, stiffness: stiffness, damping: damping),
                                  initialVelocity: initialVelocity, interpolating: true))
    }

    public static func interpolatingSpring(_ spring: Spring, initialVelocity: Double = 0) -> Animation {
        Animation(SpringAnimation(spring: spring, initialVelocity: initialVelocity, interpolating: true))
    }

    public static func interpolatingSpring(duration: TimeInterval = 0.5, bounce: Double = 0,
                                           initialVelocity: Double = 0) -> Animation {
        interpolatingSpring(Spring(duration: duration, bounce: bounce), initialVelocity: initialVelocity)
    }

    public func delay(_ delay: TimeInterval) -> Animation { Animation(DelayAnimation(animation: self, delay: delay)) }
    public func speed(_ speed: Double) -> Animation { Animation(SpeedAnimation(animation: self, speed: speed)) }

    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
        Animation(RepeatAnimation(animation: self, count: repeatCount, autoreverses: autoreverses))
    }

    public func repeatForever(autoreverses: Bool = true) -> Animation {
        Animation(RepeatAnimation(animation: self, count: nil, autoreverses: autoreverses))
    }

    public func logicallyComplete(after duration: TimeInterval) -> Animation {
        Animation(LogicallyCompleteAnimation(animation: self, after: duration))
    }
}

extension Animation: CustomAnimation {}

package struct TimingCurveAnimation: CustomAnimation, CustomStringConvertible {
    package let curve: UnitCurve
    package let duration: TimeInterval

    package func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: curve.value(at: time / duration))
    }

    package func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        guard duration > 0, time < duration else { return .zero }
        return value.scaled(by: curve.velocity(at: time / duration) / duration)
    }

    package var description: String { "curve(\(curve), duration: \(duration))" }
}

package struct SpringAnimation: CustomAnimation, CustomStringConvertible {
    package static let settleEpsilon = 2e-6

    package let spring: Spring
    package var blendDuration: TimeInterval = 0
    package var initialVelocity: Double = 0
    package var interpolating = false

    package init(spring: Spring, blendDuration: TimeInterval = 0, initialVelocity: Double = 0, interpolating: Bool = false) {
        self.spring = spring
        self.blendDuration = blendDuration
        self.initialVelocity = initialVelocity
        self.interpolating = interpolating
    }

    private func startVelocity<V: VectorArithmetic>(_ value: V, _ context: AnimationContext<V>) -> V {
        context.state.inheritedVelocity ?? value.scaled(by: initialVelocity)
    }

    package func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let v0 = startVelocity(value, context)
        if time >= spring.duration { context.isLogicallyComplete = true }
        let x = spring.value(target: value, initialVelocity: v0, time: time)
        let w0 = 2 * Double.pi / spring.response
        let scale = max(value.magnitudeSquared.squareRoot(), v0.magnitudeSquared.squareRoot() / w0)
        guard scale > 0 else { return nil }
        let distance = (value - x).magnitudeSquared.squareRoot()
        let speed = spring.velocity(target: value, initialVelocity: v0, time: time).magnitudeSquared.squareRoot() / w0
        if time > 0 && distance <= Self.settleEpsilon * scale && speed <= Self.settleEpsilon * scale { return nil }
        return x
    }

    package func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        spring.velocity(target: value, initialVelocity: startVelocity(value, context), time: time)
    }

    package func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                                  context: inout AnimationContext<V>) -> Bool {
        guard previous.base is SpringAnimation else { return false }
        context.state.inheritedVelocity = previous.velocity(value: value, time: time, context: context)
        return true
    }

    package var description: String {
        interpolating
            ? "interpolatingSpring(mass: \(spring.mass), stiffness: \(spring.stiffness), damping: \(spring.damping), initialVelocity: \(initialVelocity))"
            : "spring(response: \(spring.response), dampingFraction: \(spring.dampingRatio), blendDuration: \(blendDuration))"
    }
}

package struct DelayAnimation: CustomAnimation, CustomStringConvertible {
    package let animation: Animation
    package let delay: TimeInterval

    package func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time >= delay else { return .zero }
        return animation.animate(value: value, time: time - delay, context: &context)
    }

    package func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        guard time >= delay else { return .zero }
        return animation.velocity(value: value, time: time - delay, context: context)
    }

    package func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                                  context: inout AnimationContext<V>) -> Bool {
        animation.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }

    package var description: String { "\(animation).delay(\(delay))" }
}

package struct SpeedAnimation: CustomAnimation, CustomStringConvertible {
    package let animation: Animation
    package let speed: Double

    package func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        animation.animate(value: value, time: time * speed, context: &context)
    }

    package func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        animation.velocity(value: value, time: time * speed, context: context)?.scaled(by: speed)
    }

    package func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                                  context: inout AnimationContext<V>) -> Bool {
        animation.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }

    package var description: String { "\(animation).speed(\(speed))" }
}

package struct RepeatAnimation: CustomAnimation, CustomStringConvertible {
    package let animation: Animation
    package let count: Int?
    package let autoreverses: Bool

    private func position(_ time: TimeInterval) -> (cycle: Int, local: TimeInterval)? {
        guard let d = animation.cycleDuration(), d > 0 else { return nil }
        var k = Int((time / d).rounded(.down))
        var local = time - Double(k) * d
        if let n = count, n > 0, k == n, local <= 1e-9 {
            k = n - 1
            local = d
        }
        return (k, autoreverses && k % 2 == 1 ? d - local : local)
    }

    package func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard let p = position(time) else { return nil }
        if let n = count, p.cycle >= n { return nil }
        var inner = context
        return animation.animate(value: value, time: p.local, context: &inner) ?? value
    }

    package func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        guard let p = position(time) else { return nil }
        let v = animation.velocity(value: value, time: p.local, context: context)
        return autoreverses && p.cycle % 2 == 1 ? v?.scaled(by: -1) : v
    }

    package var description: String {
        count.map { "\(animation).repeatCount(\($0), autoreverses: \(autoreverses))" }
            ?? "\(animation).repeatForever(autoreverses: \(autoreverses))"
    }
}

package struct LogicallyCompleteAnimation: CustomAnimation, CustomStringConvertible {
    package let animation: Animation
    package let after: TimeInterval

    package func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let r = animation.animate(value: value, time: time, context: &context)
        context.isLogicallyComplete = time >= after
        return r
    }

    package func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        animation.velocity(value: value, time: time, context: context)
    }

    package func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                                  context: inout AnimationContext<V>) -> Bool {
        animation.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }

    package var description: String { "\(animation).logicallyComplete(after: \(after))" }
}
