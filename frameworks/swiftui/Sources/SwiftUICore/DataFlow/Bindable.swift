import Foundation
import Observation

@propertyWrapper
@dynamicMemberLookup
public struct Bindable<Value> {
    public var wrappedValue: Value

    public var projectedValue: Bindable<Value> { self }

    public init(wrappedValue: Value) where Value: AnyObject & Observable { self.wrappedValue = wrappedValue }

    public init(projectedValue: Bindable<Value>) { self = projectedValue }

    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject>
    where Value: AnyObject {
        objectBinding(wrappedValue, keyPath)
    }
}

extension Bindable where Value: AnyObject & Observable {
    public init(_ wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

extension Bindable: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

extension Bindable: DynamicProperty {}

extension Bindable: @unchecked Sendable {}
