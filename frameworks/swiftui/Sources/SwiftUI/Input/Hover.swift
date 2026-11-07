import Foundation
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

public enum HoverPhase: Equatable, Sendable {
    case active(CGPoint)
    case ended
}

final class HoverState: HoverHandling {
    var onHover: ((Bool) -> Void)?
    var onContinuous: ((HoverPhase) -> Void)?
    var global = false
    private var inside = false

    func hover(location: CGPoint?, frame: CGRect) {
        if let l = location {
            if !inside {
                inside = true
                onHover?(true)
            }
            onContinuous?(.active(global ? CGPoint(x: l.x + frame.minX, y: l.y + frame.minY) : l))
        } else if inside {
            inside = false
            onHover?(false)
            onContinuous?(.ended)
        }
    }
}

struct HoverModifier: PrimitiveModifier {
    let onHover: ((Bool) -> Void)?
    let onContinuous: ((HoverPhase) -> Void)?
    let global: Bool

    private func apply(_ s: HoverState) {
        s.onHover = onHover
        s.onContinuous = onContinuous
        s.global = global
    }

    func _inserted(node: ViewNode) {
        let s = HoverState()
        apply(s)
        node.primitiveState = s
    }

    func _updated(old: HoverModifier, node: ViewNode) {
        if let s = node.primitiveState as? HoverState { apply(s) }
    }
}

extension View {
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(HoverModifier(onHover: action, onContinuous: nil, global: false))
    }

    public func onContinuousHover(coordinateSpace: CoordinateSpace = .local,
                                  perform action: @escaping (HoverPhase) -> Void) -> some View {
        modifier(HoverModifier(onHover: nil, onContinuous: action, global: coordinateSpace != .local))
    }
}
