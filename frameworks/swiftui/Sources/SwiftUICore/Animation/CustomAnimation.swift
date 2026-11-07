import Foundation

public protocol CustomAnimation: Hashable, Sendable {
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V?

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V?

    func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                          context: inout AnimationContext<V>) -> Bool
}

extension CustomAnimation {
    public func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? { nil }

    public func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                                 context: inout AnimationContext<V>) -> Bool { false }
}

public protocol AnimationStateKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct AnimationState<Value: VectorArithmetic> {
    private var storage: [ObjectIdentifier: Any] = [:]
    package var inheritedVelocity: Value?

    public init() {}

    public subscript<K: AnimationStateKey>(key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(key)].map { $0 as! K.Value } ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }
}

public struct AnimationContext<Value: VectorArithmetic> {
    public var state: AnimationState<Value>
    public var isLogicallyComplete: Bool
    package var _environment: EnvironmentValues

    package init(state: AnimationState<Value> = AnimationState(), isLogicallyComplete: Bool = false,
                 environment: EnvironmentValues = EnvironmentValues()) {
        self.state = state
        self.isLogicallyComplete = isLogicallyComplete
        self._environment = environment
    }

    public var environment: EnvironmentValues { _environment }

    public func withState<T: VectorArithmetic>(_ state: AnimationState<T>) -> AnimationContext<T> {
        AnimationContext<T>(state: state, isLogicallyComplete: isLogicallyComplete, environment: _environment)
    }
}
