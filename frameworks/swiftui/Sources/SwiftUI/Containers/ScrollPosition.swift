import Foundation
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

public struct ScrollPosition: Equatable, Sendable {
    public private(set) var point: CGPoint?
    var serial = 0

    public init(point: CGPoint) { self.point = point }
    public init(x: CGFloat, y: CGFloat) { point = CGPoint(x: x, y: y) }
    public init(x: CGFloat) { point = CGPoint(x: x, y: 0) }
    public init(y: CGFloat) { point = CGPoint(x: 0, y: y) }

    public mutating func scrollTo(point: CGPoint) {
        self.point = point
        serial &+= 1
    }

    public mutating func scrollTo(x: CGFloat, y: CGFloat) { scrollTo(point: CGPoint(x: x, y: y)) }
    public mutating func scrollTo(x: CGFloat) { scrollTo(point: CGPoint(x: x, y: point?.y ?? 0)) }
    public mutating func scrollTo(y: CGFloat) { scrollTo(point: CGPoint(x: point?.x ?? 0, y: y)) }
}

private enum ScrollPointKey: EnvironmentKey {
    static var defaultValue: Binding<ScrollPosition>? { nil }
}

extension EnvironmentValues {
    var _scrollPointBinding: Binding<ScrollPosition>? {
        get { self[ScrollPointKey.self] }
        set { self[ScrollPointKey.self] = newValue }
    }
}

extension View {
    public func scrollPosition(_ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil) -> some View {
        environment(\._scrollPointBinding, position)
    }
}

extension ScrollViewState {
    @MainActor func applyScrollPoint(_ binding: Binding<ScrollPosition>?) {
        guard let binding else { return }
        let p = binding.wrappedValue
        if p.serial != appliedPointSerial {
            appliedPointSerial = p.serial
            if let point = p.point {
                pendingPoint = point
                setOffset(point)
            }
        }
    }

    @MainActor func settleScrollPoint() {
        guard let p = pendingPoint else { return }
        pendingPoint = nil
        setOffset(p)
    }
}
