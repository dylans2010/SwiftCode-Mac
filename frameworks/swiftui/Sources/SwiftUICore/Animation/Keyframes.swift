import Foundation

public struct _KeyframeSegment<Value: Animatable> {
    package enum Kind {
        case linear(UnitCurve)
        case spring(Spring, startVelocity: Value.AnimatableData?)
        case cubic(startVelocity: Value.AnimatableData?, endVelocity: Value.AnimatableData?)
        case move
    }

    package var kind: Kind
    package var target: Value.AnimatableData
    package var duration: TimeInterval
}

public protocol KeyframeTrackContent<Value> {
    associatedtype Value: Animatable
    associatedtype Body
    var _keyframeSegments: [_KeyframeSegment<Value>] { get }
}

public struct LinearKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = LinearKeyframe
    private let segment: _KeyframeSegment<Value>
    public init(_ to: Value, duration: TimeInterval, timingCurve: UnitCurve = .linear) {
        segment = _KeyframeSegment(kind: .linear(timingCurve), target: to.animatableData, duration: duration)
    }
    public var _keyframeSegments: [_KeyframeSegment<Value>] { [segment] }
}

public struct SpringKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = SpringKeyframe
    private let segment: _KeyframeSegment<Value>
    public init(_ to: Value, duration: TimeInterval? = nil, spring: Spring = Spring(), startVelocity: Value? = nil) {
        segment = _KeyframeSegment(kind: .spring(spring, startVelocity: startVelocity?.animatableData),
                                   target: to.animatableData, duration: duration ?? spring.settlingDuration)
    }
    public var _keyframeSegments: [_KeyframeSegment<Value>] { [segment] }
}

public struct CubicKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = CubicKeyframe
    private let segment: _KeyframeSegment<Value>
    public init(_ to: Value, duration: TimeInterval, startVelocity: Value? = nil, endVelocity: Value? = nil) {
        segment = _KeyframeSegment(kind: .cubic(startVelocity: startVelocity?.animatableData,
                                                endVelocity: endVelocity?.animatableData),
                                   target: to.animatableData, duration: duration)
    }
    public var _keyframeSegments: [_KeyframeSegment<Value>] { [segment] }
}

public struct MoveKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = MoveKeyframe
    private let segment: _KeyframeSegment<Value>
    public init(_ to: Value) { segment = _KeyframeSegment(kind: .move, target: to.animatableData, duration: 0) }
    public var _keyframeSegments: [_KeyframeSegment<Value>] { [segment] }
}

public struct _KeyframeList<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = _KeyframeList
    public let _keyframeSegments: [_KeyframeSegment<Value>]
    package init(_ segments: [_KeyframeSegment<Value>]) { _keyframeSegments = segments }
}

@resultBuilder
public struct KeyframeTrackContentBuilder<Value: Animatable> {
    public static func buildExpression<K: KeyframeTrackContent>(_ expression: K) -> K where K.Value == Value { expression }

    public static func buildArray(_ components: [some KeyframeTrackContent<Value>]) -> _KeyframeList<Value> {
        _KeyframeList(components.flatMap { $0._keyframeSegments })
    }

    public static func buildEither<First: KeyframeTrackContent, Second: KeyframeTrackContent>(first component: First)
        -> Conditional<First, Second> where First.Value == Value, Second.Value == Value {
        Conditional(segments: component._keyframeSegments)
    }

    public static func buildEither<First: KeyframeTrackContent, Second: KeyframeTrackContent>(second component: Second)
        -> Conditional<First, Second> where First.Value == Value, Second.Value == Value {
        Conditional(segments: component._keyframeSegments)
    }

    public static func buildPartialBlock<K: KeyframeTrackContent>(first: K) -> K where K.Value == Value { first }

    public static func buildPartialBlock(accumulated: some KeyframeTrackContent<Value>,
                                         next: some KeyframeTrackContent<Value>) -> _KeyframeList<Value> {
        _KeyframeList(accumulated._keyframeSegments + next._keyframeSegments)
    }

    public static func buildBlock() -> _KeyframeList<Value> { _KeyframeList([]) }

    public struct Conditional<First: KeyframeTrackContent, Second: KeyframeTrackContent>: KeyframeTrackContent
        where First.Value == Value, Second.Value == Value {
        public typealias Body = Conditional
        public let _keyframeSegments: [_KeyframeSegment<Value>]
        package init(segments: [_KeyframeSegment<Value>]) { _keyframeSegments = segments }
    }
}

public struct _KeyframeTrackStorage<Root> {
    package let make: (Root) -> (duration: TimeInterval, apply: (inout Root, TimeInterval) -> Void)
    package var implicitSegments: [Any]?
    package var join: (([Any]) -> _KeyframeTrackStorage<Root>)?

    package init(make: @escaping (Root) -> (duration: TimeInterval, apply: (inout Root, TimeInterval) -> Void)) {
        self.make = make
    }

    package static func implicit<V: Animatable>(_ segments: [_KeyframeSegment<V>]) -> _KeyframeTrackStorage<V> {
        var s = _KeyframeTrackStorage<V> { root in
            let curve = KeyframeCurve(initial: root.animatableData, segments: segments)
            return (curve.duration, { r, t in r.animatableData = curve.value(at: t) })
        }
        s.implicitSegments = segments
        s.join = { more in implicit(segments + more.map { $0 as! _KeyframeSegment<V> }) }
        return s
    }

    package static func concat(_ a: [_KeyframeTrackStorage<Root>], _ b: [_KeyframeTrackStorage<Root>]) -> [_KeyframeTrackStorage<Root>] {
        guard let last = a.last, let first = b.first, let join = last.join, let more = first.implicitSegments,
              first.join != nil else { return a + b }
        return a.dropLast() + [join(more)] + b.dropFirst()
    }
}

public protocol Keyframes<Value> {
    associatedtype Value
    associatedtype Body
    var _keyframeTracks: [_KeyframeTrackStorage<Value>] { get }
}

public struct KeyframeTrack<Root, Value: Animatable, Content: KeyframeTrackContent>: Keyframes where Content.Value == Value {
    public typealias Body = KeyframeTrack
    private let keyPath: WritableKeyPath<Root, Value>
    private let segments: [_KeyframeSegment<Value>]

    public init(_ keyPath: WritableKeyPath<Root, Value>, @KeyframeTrackContentBuilder<Value> content: () -> Content) {
        self.keyPath = keyPath
        segments = content()._keyframeSegments
    }

    public init(@KeyframeTrackContentBuilder<Root> content: () -> Content) where Root == Value {
        keyPath = \Root.self
        segments = content()._keyframeSegments
    }

    public var _keyframeTracks: [_KeyframeTrackStorage<Root>] {
        let keyPath = self.keyPath, segments = self.segments
        return [_KeyframeTrackStorage(make: { root in
            let curve = KeyframeCurve(initial: root[keyPath: keyPath].animatableData, segments: segments)
            return (curve.duration, { r, t in r[keyPath: keyPath].animatableData = curve.value(at: t) })
        })]
    }
}

public struct _KeyframeTracks<Value>: Keyframes {
    public typealias Body = _KeyframeTracks
    public let _keyframeTracks: [_KeyframeTrackStorage<Value>]
    package init(_ tracks: [_KeyframeTrackStorage<Value>]) { _keyframeTracks = tracks }
}

@resultBuilder
public struct KeyframesBuilder<Value> {
    public static func buildExpression<K: Keyframes>(_ expression: K) -> K where K.Value == Value { expression }

    public static func buildExpression<K: KeyframeTrackContent>(_ expression: K) -> _KeyframeTracks<Value>
        where K.Value == Value {
        _KeyframeTracks([_KeyframeTrackStorage<Value>.implicit(expression._keyframeSegments)])
    }

    public static func buildArray(_ components: [some Keyframes<Value>]) -> _KeyframeTracks<Value> {
        _KeyframeTracks(components.reduce([]) { _KeyframeTrackStorage.concat($0, $1._keyframeTracks) })
    }

    public static func buildEither(first component: some Keyframes<Value>) -> _KeyframeTracks<Value> {
        _KeyframeTracks(component._keyframeTracks)
    }

    public static func buildEither(second component: some Keyframes<Value>) -> _KeyframeTracks<Value> {
        _KeyframeTracks(component._keyframeTracks)
    }

    public static func buildPartialBlock(first: some Keyframes<Value>) -> _KeyframeTracks<Value> {
        _KeyframeTracks(first._keyframeTracks)
    }

    public static func buildPartialBlock(accumulated: some Keyframes<Value>, next: some Keyframes<Value>) -> _KeyframeTracks<Value> {
        _KeyframeTracks(_KeyframeTrackStorage.concat(accumulated._keyframeTracks, next._keyframeTracks))
    }

    public static func buildBlock() -> _KeyframeTracks<Value> { _KeyframeTracks([]) }

    public static func buildFinalResult<K: Keyframes>(_ component: K) -> K where K.Value == Value { component }
}

public struct KeyframeTimeline<Value> {
    private let initialValue: Value
    private let tracks: [(duration: TimeInterval, apply: (inout Value, TimeInterval) -> Void)]

    public init<Content: Keyframes>(initialValue: Value, @KeyframesBuilder<Value> content: () -> Content)
        where Content.Value == Value {
        self.initialValue = initialValue
        tracks = content()._keyframeTracks.map { $0.make(initialValue) }
    }

    public var duration: TimeInterval { tracks.map(\.duration).max() ?? 0 }

    public func value(time: TimeInterval) -> Value {
        var v = initialValue
        for t in tracks { t.apply(&v, time) }
        return v
    }

    public func value(progress: Double) -> Value { value(time: progress * duration) }
}

package struct KeyframeCurve<D: VectorArithmetic> {
    private enum Shape {
        case curve(UnitCurve)
        case spring(Spring, v0: D)
        case hermite(m0: D, m1: D)
    }

    private struct Piece {
        var start: TimeInterval
        var duration: TimeInterval
        var from: D
        var to: D
        var shape: Shape
    }

    private let pieces: [Piece]
    private let initial: D
    private let final: D
    package let duration: TimeInterval

    package init<Value: Animatable>(initial: D, segments: [_KeyframeSegment<Value>]) where Value.AnimatableData == D {
        var pieces: [Piece] = []
        var value = initial
        var velocity = D.zero
        var t: TimeInterval = 0
        for (i, seg) in segments.enumerated() {
            let d = max(seg.duration, 0)
            switch seg.kind {
            case .move:
                value = seg.target
                velocity = .zero
                continue
            case .linear(let curve):
                pieces.append(Piece(start: t, duration: d, from: value, to: seg.target, shape: .curve(curve)))
                velocity = d > 0 ? (seg.target - value).scaled(by: curve.velocity(at: 1) / d) : .zero
                value = seg.target
            case .spring(let spring, let sv):
                let v0 = sv ?? velocity
                pieces.append(Piece(start: t, duration: d, from: value, to: seg.target, shape: .spring(spring, v0: v0)))
                let end = spring.value(fromValue: value, toValue: seg.target, initialVelocity: v0, time: d)
                velocity = spring.velocity(fromValue: value, toValue: seg.target, initialVelocity: v0, time: d)
                value = end
            case .cubic(let sv, let ev):
                let m0 = sv ?? velocity
                let m1 = ev ?? KeyframeCurve.endSlope(after: i, start: value, segments: segments)
                pieces.append(Piece(start: t, duration: d, from: value, to: seg.target, shape: .hermite(m0: m0, m1: m1)))
                velocity = m1
                value = seg.target
            }
            t += d
        }
        self.pieces = pieces
        self.initial = initial
        self.final = value
        self.duration = t
    }

    private static func endSlope<Value: Animatable>(after i: Int, start: D, segments: [_KeyframeSegment<Value>]) -> D
        where Value.AnimatableData == D {
        guard i + 1 < segments.count else { return .zero }
        let this = segments[i], next = segments[i + 1]
        switch next.kind {
        case .cubic:
            let span = this.duration + next.duration
            return span > 0 ? (next.target - start).scaled(by: 1 / span) : .zero
        case .linear(let curve):
            return next.duration > 0 ? (next.target - this.target).scaled(by: curve.velocity(at: 0) / next.duration) : .zero
        case .spring(_, let sv):
            return sv ?? .zero
        case .move:
            return .zero
        }
    }

    package func value(at time: TimeInterval) -> D {
        if time <= 0 { return initial }
        for p in pieces where time <= p.start + p.duration {
            let tau = max(0, time - p.start)
            switch p.shape {
            case .curve(let c):
                return p.duration > 0 ? p.from + (p.to - p.from).scaled(by: c.value(at: tau / p.duration)) : p.to
            case .spring(let s, let v0):
                return s.value(fromValue: p.from, toValue: p.to, initialVelocity: v0, time: tau)
            case .hermite(let m0, let m1):
                guard p.duration > 0 else { return p.to }
                let u = tau / p.duration, u2 = u * u, u3 = u2 * u
                let h00 = 2 * u3 - 3 * u2 + 1, h10 = u3 - 2 * u2 + u
                let h01 = -2 * u3 + 3 * u2, h11 = u3 - u2
                return p.from.scaled(by: h00) + m0.scaled(by: h10 * p.duration)
                    + p.to.scaled(by: h01) + m1.scaled(by: h11 * p.duration)
            }
        }
        return final
    }
}
