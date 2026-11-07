import Foundation
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

public struct DragGesture: Gesture {
    public typealias Body = Never
    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace

    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
    }

    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var velocity: CGSize

        public var translation: CGSize {
            CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y)
        }

        public var predictedEndTranslation: CGSize {
            CGSize(width: translation.width + DragRecognizer.predictionInterval * velocity.width,
                   height: translation.height + DragRecognizer.predictionInterval * velocity.height)
        }

        public var predictedEndLocation: CGPoint {
            CGPoint(x: startLocation.x + predictedEndTranslation.width,
                    y: startLocation.y + predictedEndTranslation.height)
        }

        package init(time: Date, location: CGPoint, startLocation: CGPoint, velocity: CGSize) {
            self.time = time
            self.location = location
            self.startLocation = startLocation
            self.velocity = velocity
        }
    }
}

extension DragGesture: PrimitiveGesture {
    package func _makeRecognizer(context: GestureContext) -> GestureRecognizer {
        let recognizer = DragRecognizer(minimumDistance: minimumDistance, global: coordinateSpace != .local,
                                        context: context)
        return mapping(recognizer) { (s: DragSample) -> Value in
            Value(time: Date(timeIntervalSinceReferenceDate: s.time), location: s.location,
                  startLocation: s.startLocation, velocity: s.velocity)
        }
    }
}

public struct LongPressGesture: Gesture {
    public typealias Value = Bool
    public typealias Body = Never
    public var minimumDuration: Double
    public var maximumDistance: CGFloat

    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }
}

extension LongPressGesture: PrimitiveGesture {
    package func _makeRecognizer(context: GestureContext) -> GestureRecognizer {
        LongPressRecognizer(minimumDuration: minimumDuration, maximumDistance: maximumDistance, context: context)
    }
}

struct LongPressActionGesture: Gesture, PrimitiveGesture {
    typealias Value = Bool
    typealias Body = Never
    let minimumDuration: Double
    let maximumDistance: CGFloat
    let action: () -> Void
    let pressingChanged: ((Bool) -> Void)?

    func _makeRecognizer(context: GestureContext) -> GestureRecognizer {
        LongPressActionRecognizer(minimumDuration: minimumDuration, maximumDistance: maximumDistance, context: context,
                                  action: action, pressingChanged: pressingChanged)
    }
}

extension View {
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10,
                                   perform action: @escaping () -> Void,
                                   onPressingChanged: ((Bool) -> Void)? = nil) -> some View {
        gesture(LongPressActionGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance,
                                       action: action, pressingChanged: onPressingChanged))
    }

    @available(*, deprecated, renamed: "onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)")
    @_disfavoredOverload
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10,
                                   pressing: ((Bool) -> Void)? = nil,
                                   perform action: @escaping () -> Void) -> some View {
        gesture(LongPressActionGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance,
                                       action: action, pressingChanged: pressing))
    }
}

public struct SpatialTapGesture: Gesture {
    public typealias Body = Never
    public var count: Int
    public var coordinateSpace: CoordinateSpace

    public init(count: Int = 1, coordinateSpace: CoordinateSpace = .local) {
        self.count = count
        self.coordinateSpace = coordinateSpace
    }

    public struct Value: Equatable, Sendable {
        public var location: CGPoint
    }
}

extension SpatialTapGesture: PrimitiveGesture {
    package func _makeRecognizer(context: GestureContext) -> GestureRecognizer {
        let local = coordinateSpace == .local, origin = context.frame.origin
        return mapping(TapRecognizer(count: count, context: context)) { (p: CGPoint) -> Value in
            Value(location: local ? p : CGPoint(x: p.x + origin.x, y: p.y + origin.y))
        }
    }
}

public struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture {
    public typealias Body = Never
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public enum Value {
        case first(First.Value)
        case second(First.Value, Second.Value?)
    }
}

extension SequenceGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}

extension SequenceGesture: PrimitiveGesture {
    package func _makeRecognizer(context: GestureContext) -> GestureRecognizer {
        SequenceRecognizer(GestureFactory.make(first, context: context), GestureFactory.make(second, context: context),
                           first: { Value.first($0 as! First.Value) },
                           second: { Value.second($0 as! First.Value, $1.map { $0 as! Second.Value }) })
    }
}

extension Gesture {
    public func sequenced<Other: Gesture>(before other: Other) -> SequenceGesture<Self, Other> {
        SequenceGesture(self, other)
    }
}

@propertyWrapper
public struct GestureState<Value>: DynamicProperty {
    package let box: StateBox<Value>
    package let resetTransaction: Transaction

    public init(wrappedValue: Value) { self.init(wrappedValue: wrappedValue, resetTransaction: Transaction()) }
    public init(initialValue: Value) { self.init(wrappedValue: initialValue, resetTransaction: Transaction()) }
    public init(initialValue: Value, resetTransaction: Transaction) {
        self.init(wrappedValue: initialValue, resetTransaction: resetTransaction)
    }

    public init(wrappedValue: Value, resetTransaction: Transaction) {
        box = StateBox(wrappedValue)
        self.resetTransaction = resetTransaction
    }

    public var wrappedValue: Value { box.location?.read() ?? box.initial }
    public var projectedValue: GestureState<Value> { self }
}

extension GestureState where Value: ExpressibleByNilLiteral {
    public init(resetTransaction: Transaction = Transaction()) {
        self.init(wrappedValue: nil, resetTransaction: resetTransaction)
    }
}

extension GestureState: @unchecked Sendable {}

extension GestureState: GraphDynamicProperty {
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

extension GestureState: GraphInputComparable {
    package func _isGraphInputEqual(to other: Any) -> Bool { true }
}

public struct GestureStateGesture<Base: Gesture, State>: Gesture {
    public typealias Value = Base.Value
    public typealias Body = Never
    public var base: Base
    public var state: GestureState<State>
    public var body: (GestureStateGesture<Base, State>.Value, inout State, inout Transaction) -> Void

    public init(base: Base, state: GestureState<State>,
                body: @escaping (GestureStateGesture<Base, State>.Value, inout State, inout Transaction) -> Void) {
        self.base = base
        self.state = state
        self.body = body
    }
}

extension GestureStateGesture: PrimitiveGesture {
    package func _makeRecognizer(context: GestureContext) -> GestureRecognizer {
        let state = state, body = body
        return UpdatingRecognizer(base: GestureFactory.make(base, context: context), update: { v in
            guard let loc = state.box.location else { return }
            var s = loc.value
            var tx = Transaction()
            body(v as! Base.Value, &s, &tx)
            loc.write(s, transaction: tx)
        }, reset: {
            state.box.location?.write(state.box.initial, transaction: state.resetTransaction)
        })
    }
}

extension Gesture {
    public func updating<State>(_ state: GestureState<State>,
                                body: @escaping (Value, inout State, inout Transaction) -> Void)
        -> GestureStateGesture<Self, State> {
        GestureStateGesture(base: self, state: state, body: body)
    }
}
