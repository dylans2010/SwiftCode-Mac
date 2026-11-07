import Foundation

package struct PointerSample: Equatable {
    package enum Phase: Equatable { case down, moved, up, cancelled }
    package var pointer: Int
    package var phase: Phase
    package var location: CGPoint
    package var time: TimeInterval
    package var isTouch: Bool

    package init(pointer: Int = 0, phase: Phase, location: CGPoint, time: TimeInterval, isTouch: Bool = false) {
        self.pointer = pointer
        self.phase = phase
        self.location = location
        self.time = time
        self.isTouch = isTouch
    }
}

package enum GestureInput: Equatable {
    case pointer(PointerSample)
    case tick(TimeInterval)

    package var time: TimeInterval {
        switch self {
        case .pointer(let p): return p.time
        case .tick(let t): return t
        }
    }
}

package enum GesturePhase: Equatable {
    case possible
    case active
    case ended
    case failed

    package var isResolved: Bool { self == .ended || self == .failed }
}

package struct GestureContext {
    package var frame: CGRect
    package init(frame: CGRect) { self.frame = frame }

    package func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - frame.minX, y: p.y - frame.minY) }
}

@MainActor
package protocol AnyGestureRecognizer: AnyObject {
    var phase: GesturePhase { get }
    var defersLowerPriority: Bool { get }
    var deadline: TimeInterval? { get }
    func handle(_ input: GestureInput)
    func flush()
    func cancel()
}

@MainActor
package class GestureRecognizer: AnyGestureRecognizer {
    package var phase: GesturePhase = .possible
    package var value: Any?
    package var provisionalValue: Any?
    package var context: GestureContext

    package init(context: GestureContext) { self.context = context }

    package var defersLowerPriority: Bool { false }
    package var deadline: TimeInterval? { nil }
    package func handle(_ input: GestureInput) {}
    package func flush() {}
    package func cancel() {
        if !phase.isResolved { phase = .failed }
    }

    package var currentValue: Any? {
        switch phase {
        case .active, .ended: return value
        case .possible: return provisionalValue
        case .failed: return nil
        }
    }

    package func fail() {
        if !phase.isResolved { phase = .failed }
    }
}

@MainActor
package class WrappingRecognizer: GestureRecognizer {
    package let base: GestureRecognizer
    package let transform: (Any) -> Any

    package init(base: GestureRecognizer, transform: @escaping (Any) -> Any = { $0 }) {
        self.base = base
        self.transform = transform
        super.init(context: base.context)
    }

    override package var defersLowerPriority: Bool { base.defersLowerPriority }
    override package var deadline: TimeInterval? { base.deadline }

    override package func handle(_ input: GestureInput) {
        base.handle(input)
        sync()
    }

    package func sync() {
        phase = base.phase
        value = base.value.map(transform)
        provisionalValue = base.provisionalValue.map(transform)
    }

    override package func flush() {
        base.flush()
        sync()
    }

    override package func cancel() {
        base.cancel()
        sync()
    }
}

@MainActor
package func mapping<A, B>(_ base: GestureRecognizer, _ f: @escaping (A) -> B) -> GestureRecognizer {
    WrappingRecognizer(base: base) { f($0 as! A) }
}

@MainActor
package protocol PrimitiveGesture: Gesture {
    func _makeRecognizer(context: GestureContext) -> GestureRecognizer
}

@MainActor
package enum GestureFactory {
    package static func make<G: Gesture>(_ gesture: G, context: GestureContext) -> GestureRecognizer {
        if let p = gesture as? any PrimitiveGesture { return p._makeRecognizer(context: context) }
        return make(gesture.body, context: context)
    }
}

package enum GestureAttachmentKind: Equatable {
    case normal
    case highPriority
    case simultaneous
}

@MainActor
package final class GestureAttachment {
    package var kind: GestureAttachmentKind
    package var mask: GestureMask
    package var isEnabled: Bool
    package var make: (GestureContext) -> GestureRecognizer

    package init(kind: GestureAttachmentKind, mask: GestureMask, isEnabled: Bool,
                 make: @escaping (GestureContext) -> GestureRecognizer) {
        self.kind = kind
        self.mask = mask
        self.isEnabled = isEnabled
        self.make = make
    }
}

@MainActor
package final class GestureSession {
    package struct Member {
        package let recognizer: any AnyGestureRecognizer
        package let simultaneous: Bool
        package var cancelled = false
    }

    package private(set) var members: [Member]
    package private(set) var winner: Int?
    package private(set) var pointersDown: Set<Int> = []
    package var nodes: Set<ObjectIdentifier> = []

    package init(members: [Member]) { self.members = members }

    package var isFinished: Bool {
        pointersDown.isEmpty && members.allSatisfy { $0.cancelled || $0.recognizer.phase.isResolved }
    }

    package var deadline: TimeInterval? {
        members.filter { !$0.cancelled }.compactMap { $0.recognizer.deadline }.min()
    }

    package func handle(_ input: GestureInput) {
        if case .pointer(let p) = input {
            switch p.phase {
            case .down: pointersDown.insert(p.pointer)
            case .up, .cancelled: pointersDown.remove(p.pointer)
            case .moved: break
            }
        }
        for m in members where !m.cancelled { m.recognizer.handle(input) }
        resolve()
    }

    package func cancelAll() {
        for i in members.indices where !members[i].cancelled {
            members[i].cancelled = true
            members[i].recognizer.cancel()
        }
        pointersDown = []
    }

    private func resolve() {
        if winner == nil {
            var deferring = false
            for (i, m) in members.enumerated() where !m.simultaneous && !m.cancelled {
                let r = m.recognizer
                if (r.phase == .active || r.phase == .ended) && !deferring {
                    winner = i
                    break
                }
                if r.phase == .possible && r.defersLowerPriority { deferring = true }
            }
            if let w = winner {
                for i in members.indices where i != w && !members[i].simultaneous && !members[i].cancelled {
                    members[i].cancelled = true
                    members[i].recognizer.cancel()
                }
            }
        }
        for i in members.indices where !members[i].cancelled {
            let r = members[i].recognizer
            if members[i].simultaneous || i == winner {
                r.flush()
            } else if r.phase == .possible {
                r.flush()
            } else if r.phase == .failed {
                members[i].cancelled = true
                r.cancel()
            }
        }
    }
}
