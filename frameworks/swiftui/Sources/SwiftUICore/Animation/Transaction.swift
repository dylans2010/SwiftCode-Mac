import Foundation

public protocol TransactionKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct AnimationCompletionCriteria: Hashable, Sendable {
    private enum Kind: Hashable, Sendable { case logicallyComplete, removed }
    private let kind: Kind
    public static let logicallyComplete = AnimationCompletionCriteria(kind: .logicallyComplete)
    public static let removed = AnimationCompletionCriteria(kind: .removed)
}

public struct Transaction {
    private var values: [ObjectIdentifier: Any] = [:]
    package var completions: [AnimationCompletionRecord] = []

    public init() {}

    public init(animation: Animation?) {
        self.init()
        self.animation = animation
    }

    public subscript<K: TransactionKey>(key: K.Type) -> K.Value {
        get {
            guard let v = values[ObjectIdentifier(key)] else { return K.defaultValue }
            return v as! K.Value
        }
        set { values[ObjectIdentifier(key)] = newValue }
    }

    public var isEmpty: Bool { values.isEmpty && completions.isEmpty }

    public var animation: Animation? {
        get { self[AnimationKey.self] }
        set { self[AnimationKey.self] = newValue }
    }

    public var disablesAnimations: Bool {
        get { self[DisablesAnimationsKey.self] }
        set { self[DisablesAnimationsKey.self] = newValue }
    }

    public var isContinuous: Bool {
        get { self[IsContinuousKey.self] }
        set { self[IsContinuousKey.self] = newValue }
    }

    public var tracksVelocity: Bool {
        get { self[TracksVelocityKey.self] }
        set { self[TracksVelocityKey.self] = newValue }
    }

    public mutating func addAnimationCompletion(criteria: AnimationCompletionCriteria = .logicallyComplete,
                                                _ completion: @escaping () -> Void) {
        completions.append(AnimationCompletionRecord(criteria: criteria, action: completion))
    }

    nonisolated(unsafe) private static var stack: [Transaction] = []

    package static var _current: Transaction {
        guard MainActorCheck.isCurrent else { return Transaction() }
        return stack.last ?? Transaction()
    }

    package static func _with<R>(_ t: Transaction, _ body: () throws -> R) rethrows -> R {
        guard MainActorCheck.isCurrent else { return try body() }
        stack.append(t)
        defer { stack.removeLast() }
        return try body()
    }
}

private enum AnimationKey: TransactionKey { static var defaultValue: Animation? { nil } }
private enum DisablesAnimationsKey: TransactionKey { static var defaultValue: Bool { false } }
private enum IsContinuousKey: TransactionKey { static var defaultValue: Bool { false } }
private enum TracksVelocityKey: TransactionKey { static var defaultValue: Bool { false } }

public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    try Transaction._with(transaction, body)
}

public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V,
                                  _ body: () throws -> R) rethrows -> R {
    var t = Transaction._current
    t[keyPath: keyPath] = value
    return try Transaction._with(t, body)
}

public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    var t = Transaction._current
    t.animation = animation
    return try Transaction._with(t, body)
}

public func withAnimation<Result>(_ animation: Animation? = .default,
                                  completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
                                  _ body: () throws -> Result, completion: @escaping () -> Void) rethrows -> Result {
    var t = Transaction._current
    t.animation = animation
    t.addAnimationCompletion(criteria: completionCriteria, completion)
    return try Transaction._with(t, body)
}
