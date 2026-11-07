import Foundation

public protocol DynamicProperty {
    mutating func update()
}

extension DynamicProperty {
    public mutating func update() {}
}

@MainActor
package protocol GraphDynamicProperty {
    func _install(in node: ViewNode, slot: Int)
}

@MainActor
package enum DynamicPropertyInstaller {
    package static func install(_ value: Any, in node: ViewNode) {
        var slot = 0
        walk(value, node, &slot, depth: 0)
    }

    private static func walk(_ value: Any, _ node: ViewNode, _ slot: inout Int, depth: Int) {
        for child in Mirror(reflecting: value).children {
            if let p = child.value as? any GraphDynamicProperty {
                p._install(in: node, slot: slot)
                slot += 1
            } else if depth < 8, let d = child.value as? any DynamicProperty {
                walk(d, node, &slot, depth: depth + 1)
                callUpdate(d)
            }
        }
    }

    private static func callUpdate<D: DynamicProperty>(_ d: D) {
        var copy = d
        copy.update()
    }
}

package final class StateLocation<Value>: DependencySource, @unchecked Sendable {
    package private(set) var value: Value
    package var onChange: (@MainActor () -> Void)?

    package init(_ value: Value) { self.value = value }

    package func read() -> Value {
        DependencyTracker.recordRead(self)
        return value
    }

    package func write(_ newValue: Value, transaction: Transaction?) {
        if MainActorCheck.isCurrent {
            let box = UncheckedBox((newValue, transaction ?? Transaction._current))
            MainActor.assumeIsolated { apply(box.value.0, box.value.1) }
        } else {
            let box = UncheckedBox(newValue)
            Task { @MainActor in self.apply(box.value, Transaction()) }
        }
    }

    @MainActor private func apply(_ newValue: Value, _ tx: Transaction) {
        let same = GraphComparison.valuesEqual(value, newValue)
        value = newValue
        if !same {
            invalidateDependents(transaction: tx)
            onChange?()
        }
    }
}

package final class UncheckedBox<T>: @unchecked Sendable {
    package let value: T
    package init(_ value: T) { self.value = value }
}

package final class StateBox<Value>: @unchecked Sendable {
    package let initial: Value
    package var location: StateLocation<Value>?

    package init(_ initial: Value) { self.initial = initial }
}

@propertyWrapper
public struct State<Value>: DynamicProperty {
    package let box: StateBox<Value>

    public init(wrappedValue value: Value) { box = StateBox(value) }
    public init(initialValue value: Value) { box = StateBox(value) }

    public var wrappedValue: Value {
        get { box.location?.read() ?? box.initial }
        nonmutating set { box.location?.write(newValue, transaction: nil) }
    }

    public var projectedValue: Binding<Value> {
        guard let loc = box.location else { return .constant(box.initial) }
        return Binding(location: loc)
    }
}

extension State where Value: ExpressibleByNilLiteral {
    public init() { self.init(wrappedValue: nil) }
}

extension State: @unchecked Sendable {}

extension State: GraphDynamicProperty {
    package func _install(in node: ViewNode, slot: Int) {
        if let loc = node.slots[slot] as? StateLocation<Value> {
            box.location = loc
        } else {
            let loc = StateLocation(box.initial)
            node.slots[slot] = loc
            box.location = loc
        }
    }
}

extension State: GraphInputComparable {
    package func _isGraphInputEqual(to other: Any) -> Bool { true }
}

@propertyWrapper
public struct Namespace: DynamicProperty, Sendable {
    public struct ID: Hashable, Sendable {
        public let id: Int
    }

    package let box = NamespaceBox()

    public init() {}

    public var wrappedValue: Namespace.ID {
        if let id = box.id { return ID(id: id) }
        return ID(id: NamespaceBox.next())
    }
}

package final class NamespaceBox: @unchecked Sendable {
    package var id: Int?
    nonisolated(unsafe) private static var counter = 0
    private static let lock = NSLock()
    package static func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        return counter
    }
    package init() {}
}

private final class NamespaceSlot {
    let id = NamespaceBox.next()
}

extension Namespace: GraphDynamicProperty {
    package func _install(in node: ViewNode, slot: Int) {
        let s = (node.slots[slot] as? NamespaceSlot) ?? NamespaceSlot()
        node.slots[slot] = s
        box.id = s.id
    }
}

extension Namespace: GraphInputComparable {
    package func _isGraphInputEqual(to other: Any) -> Bool { true }
}
