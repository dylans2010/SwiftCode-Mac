import Foundation
import Observation

package final class EnvironmentBox<Value>: @unchecked Sendable {
    package let key: AnyHashable
    package let read: (EnvironmentValues) -> Value
    package weak var node: ViewNode?
    package var snapshot: EnvironmentValues?

    package init(key: AnyHashable, read: @escaping (EnvironmentValues) -> Value) {
        self.key = key
        self.read = read
    }

    @MainActor package func resolve() -> Value {
        let env = node?.environment ?? snapshot ?? EnvironmentValues()
        let v = read(env)
        let read = self.read
        DependencyTracker.recordEnvironmentRead(node: node, key: key, value: v, read: { read($0) })
        return v
    }
}

@propertyWrapper
public struct Environment<Value>: DynamicProperty {
    package let box: EnvironmentBox<Value>

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        box = EnvironmentBox(key: AnyHashable(keyPath), read: { $0[keyPath: keyPath] })
    }

    public var wrappedValue: Value {
        guard MainActorCheck.isCurrent else { return box.read(box.snapshot ?? EnvironmentValues()) }
        let box = self.box
        return MainActor.assumeIsolated { UncheckedBox(box.resolve()) }.value
    }
}

extension Environment where Value: AnyObject & Observable {
    public init(_ objectType: Value.Type) {
        box = EnvironmentBox(key: AnyHashable(ObjectIdentifier(objectType))) { env in
            guard let o = env[objectType: objectType] else {
                fatalError("No Observable object of type \(Value.self) found. A View.environment(_:) for \(Value.self) may be missing as an ancestor of this view.")
            }
            return o
        }
    }
}

extension Environment {
    public init<T: AnyObject & Observable>(_ objectType: T.Type) where Value == T? {
        box = EnvironmentBox(key: AnyHashable(ObjectIdentifier(objectType))) { $0[objectType: objectType] }
    }
}

extension Environment: @unchecked Sendable {}

extension Environment: GraphDynamicProperty {
    package func _install(in node: ViewNode, slot: Int) {
        box.node = node
        box.snapshot = node.environment
    }
}

extension Environment: GraphInputComparable {
    package func _isGraphInputEqual(to other: Any) -> Bool { true }
}

private enum ObservableObjectEnvironmentKey<T: AnyObject>: EnvironmentKey {
    static var defaultValue: T? { nil }
}

extension EnvironmentValues {
    public subscript<T: AnyObject>(objectType objectType: T.Type) -> T? {
        get { self[ObservableObjectEnvironmentKey<T>.self] }
        set { self[ObservableObjectEnvironmentKey<T>.self] = newValue }
    }
}

extension View {
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some View {
        modifier(EnvironmentTransformModifier(label: "object \(T.self)", value: object.map(ObjectIdentifier.init)) {
            $0[objectType: T.self] = object
        })
    }

    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        modifier(EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }

    public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>,
                                        transform: @escaping (inout V) -> Void) -> some View {
        modifier(EnvironmentTransformModifier(label: "transform", value: nil) { transform(&$0[keyPath: keyPath]) })
    }
}

package struct EnvironmentKeyWritingModifier<Value>: PrimitiveModifier {
    package let keyPath: WritableKeyPath<EnvironmentValues, Value>
    package let value: Value

    package var _writesEnvironment: Bool { true }

    package func _environment(_ env: EnvironmentValues) -> EnvironmentValues {
        var e = env
        e[keyPath: keyPath] = value
        return e
    }
}

package struct EnvironmentTransformModifier {
    package let label: String
    package let value: AnyHashable?
    package let transform: (inout EnvironmentValues) -> Void

    package init(label: String, value: AnyHashable?, transform: @escaping (inout EnvironmentValues) -> Void) {
        self.label = label
        self.value = value
        self.transform = transform
    }
}

extension EnvironmentTransformModifier: PrimitiveModifier {
    package var _writesEnvironment: Bool { true }

    package func _environment(_ env: EnvironmentValues) -> EnvironmentValues {
        var e = env
        transform(&e)
        return e
    }
}

extension EnvironmentTransformModifier: GraphInputComparable {
    package func _isGraphInputEqual(to other: Any) -> Bool {
        guard let o = other as? EnvironmentTransformModifier, let v = value else { return false }
        return o.label == label && o.value == v
    }
}
