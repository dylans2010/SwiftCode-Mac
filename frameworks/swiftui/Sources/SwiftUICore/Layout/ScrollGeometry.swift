import Foundation

public struct ScrollGeometry: Equatable, Sendable {
    public var contentOffset: CGPoint
    public var contentSize: CGSize
    public var contentInsets: EdgeInsets
    public var containerSize: CGSize

    public init(contentOffset: CGPoint, contentSize: CGSize, contentInsets: EdgeInsets, containerSize: CGSize) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }

    public var visibleRect: CGRect {
        CGRect(x: contentOffset.x - contentInsets.leading, y: contentOffset.y - contentInsets.top,
               width: containerSize.width + contentInsets.horizontal, height: containerSize.height + contentInsets.vertical)
    }

    public var bounds: CGRect { CGRect(origin: contentOffset, size: containerSize) }
}

public struct ScrollTarget: Hashable, Sendable {
    public var rect: CGRect
    public var anchor: UnitPoint?

    public init(rect: CGRect, anchor: UnitPoint? = nil) {
        self.rect = rect
        self.anchor = anchor
    }

    public static func == (a: ScrollTarget, b: ScrollTarget) -> Bool { a.rect == b.rect && a.anchor == b.anchor }

    public func hash(into h: inout Hasher) {
        h.combine(Double(rect.minX))
        h.combine(Double(rect.minY))
        h.combine(Double(rect.width))
        h.combine(Double(rect.height))
    }
}

public struct ScrollIndicatorVisibility: Equatable, Sendable {
    package enum Kind: Equatable, Sendable { case automatic, visible, hidden, never }
    package let kind: Kind
    public static let automatic = ScrollIndicatorVisibility(kind: .automatic)
    public static let visible = ScrollIndicatorVisibility(kind: .visible)
    public static let hidden = ScrollIndicatorVisibility(kind: .hidden)
    public static let never = ScrollIndicatorVisibility(kind: .never)
}

private enum VerticalIndicatorKey: EnvironmentKey { static let defaultValue = ScrollIndicatorVisibility.automatic }
private enum HorizontalIndicatorKey: EnvironmentKey { static let defaultValue = ScrollIndicatorVisibility.automatic }
private enum ScrollEnabledKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    public var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { self[VerticalIndicatorKey.self] }
        set { self[VerticalIndicatorKey.self] = newValue }
    }

    public var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { self[HorizontalIndicatorKey.self] }
        set { self[HorizontalIndicatorKey.self] = newValue }
    }

    public var isScrollEnabled: Bool {
        get { self[ScrollEnabledKey.self] }
        set { self[ScrollEnabledKey.self] = newValue }
    }
}

extension View {
    public func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View {
        transformEnvironment(\.self) { env in
            if axes.contains(.vertical) { env.verticalScrollIndicatorVisibility = visibility }
            if axes.contains(.horizontal) { env.horizontalScrollIndicatorVisibility = visibility }
        }
    }

    public func scrollDisabled(_ disabled: Bool) -> some View {
        transformEnvironment(\.isScrollEnabled) { if disabled { $0 = false } }
    }
}

#if !canImport(CoreGraphics)
public struct CGVector: Equatable, Hashable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init() { dx = 0; dy = 0 }
    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }
    public static var zero: CGVector { CGVector() }
}
#endif
