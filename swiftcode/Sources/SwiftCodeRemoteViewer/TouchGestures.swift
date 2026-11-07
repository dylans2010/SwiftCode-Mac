import Foundation
import SwiftCodeDisplayStream

public struct ViewPoint: Equatable, Sendable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { (self.x, self.y) = (x, y) }
}

public enum TouchGesture: Equatable, Sendable {
    case one
    case pinch
    case pan(dx: Double, dy: Double)

    public static func starting(at p: ViewPoint, center c: ViewPoint, multiTouch: Bool, shift: Bool) -> TouchGesture {
        guard multiTouch else { return .one }
        guard shift else { return .pinch }
        return .pan(dx: 2 * c.x - 2 * p.x, dy: 2 * c.y - 2 * p.y)
    }

    public func positions(_ p: ViewPoint, center c: ViewPoint) -> [ViewPoint] {
        switch self {
        case .one: [p]
        case .pinch: [p, ViewPoint(x: 2 * c.x - p.x, y: 2 * c.y - p.y)]
        case .pan(let dx, let dy): [p, ViewPoint(x: p.x + dx, y: p.y + dy)]
        }
    }
}

public struct TouchMapper: Sendable {
    public var viewWidth: Double
    public var viewHeight: Double
    public var pointWidth: Double
    public var pointHeight: Double
    public var panel: DisplayPanelState?

    public private(set) var gesture: TouchGesture?
    public private(set) var last = ViewPoint(x: 0, y: 0)
    public private(set) var scrollFinger: ViewPoint?
    public private(set) var lastScroll: Double = 0
    public static let scrollIdle = 0.15

    public init(viewWidth: Double, viewHeight: Double, pointWidth: Double, pointHeight: Double, panel: DisplayPanelState? = nil) {
        (self.viewWidth, self.viewHeight, self.pointWidth, self.pointHeight, self.panel) = (viewWidth, viewHeight, pointWidth, pointHeight, panel)
    }

    public var center: ViewPoint { ViewPoint(x: viewWidth / 2, y: viewHeight / 2) }
    public var isTouching: Bool { gesture != nil || scrollFinger != nil }

    public func devicePoint(_ p: ViewPoint) -> (x: Double, y: Double) {
        guard viewWidth > 0, viewHeight > 0 else { return (0, 0) }
        let x = min(max(p.x, 0), viewWidth) / viewWidth * pointWidth
        let y = min(max(p.y, 0), viewHeight) / viewHeight * pointHeight
        if let panel, panel.quarterTurns != 0 { return panel.nativePoint(shownX: x, shownY: y) }
        return (x, y)
    }

    public func contacts(_ points: [ViewPoint], _ phase: TouchPhase) -> [TouchContact] {
        points.enumerated().map { i, p in
            let d = devicePoint(p)
            return TouchContact(finger: UInt8(i), phase: phase, x: Float(d.x), y: Float(d.y))
        }
    }

    public func contains(_ p: ViewPoint) -> Bool { p.x >= 0 && p.y >= 0 && p.x <= viewWidth && p.y <= viewHeight }

    public mutating func down(_ p: ViewPoint, multiTouch: Bool, shift: Bool) -> [TouchContact] {
        var out = endScroll() ?? []
        let g = TouchGesture.starting(at: p, center: center, multiTouch: multiTouch, shift: shift)
        gesture = g
        last = p
        out = contacts(g.positions(p, center: center), .began)
        return out
    }

    public mutating func drag(_ p: ViewPoint) -> [TouchContact]? {
        guard let g = gesture else { return nil }
        last = p
        return contacts(g.positions(p, center: center), .moved)
    }

    public mutating func up(_ p: ViewPoint) -> [TouchContact]? {
        guard let g = gesture else { return nil }
        gesture = nil
        last = p
        return contacts(g.positions(p, center: center), .ended)
    }

    public mutating func cancel() -> [TouchContact]? {
        if let g = gesture {
            gesture = nil
            return contacts(g.positions(last, center: center), .cancelled)
        }
        return endScroll()
    }

    public func indicator(hover p: ViewPoint?, multiTouch: Bool) -> [ViewPoint] {
        if let g = gesture { return g == .one ? [] : g.positions(last, center: center) }
        guard multiTouch, let p, contains(p) else { return [] }
        return TouchGesture.pinch.positions(p, center: center)
    }

    public mutating func scroll(at p: ViewPoint, dx: Double, dy: Double, now: Double) -> [[TouchContact]] {
        guard gesture == nil else { return [] }
        var out: [[TouchContact]] = []
        if scrollFinger == nil {
            scrollFinger = p
            out.append(contacts([p], .began))
        }
        var f = scrollFinger!
        f.x = min(max(f.x + dx, 0), viewWidth)
        f.y = min(max(f.y + dy, 0), viewHeight)
        scrollFinger = f
        lastScroll = now
        out.append(contacts([f], .moved))
        return out
    }

    public mutating func endScroll() -> [TouchContact]? {
        guard let f = scrollFinger else { return nil }
        scrollFinger = nil
        return contacts([f], .ended)
    }

    public mutating func endIdleScroll(now: Double) -> [TouchContact]? {
        guard scrollFinger != nil, now - lastScroll >= Self.scrollIdle else { return nil }
        return endScroll()
    }

    public static func crownDelta(scrollingDeltaY: Double, precise: Bool, factor: Double = 2) -> Double {
        -scrollingDeltaY * (precise ? 1 : 10) * factor
    }
}
