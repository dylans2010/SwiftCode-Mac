import Foundation

package struct SpacingPreference: Hashable, Sendable {
    package enum Kind: Hashable, Sendable {
        case standard
        case text
        case image
    }

    package var kind: Kind
    package var towardStandard: CGFloat
    package var towardText: CGFloat

    package init(kind: Kind, towardStandard: CGFloat, towardText: CGFloat = 0) {
        self.kind = kind
        self.towardStandard = towardStandard
        self.towardText = towardText
    }

    package static let standard = SpacingPreference(kind: .standard, towardStandard: 8)

    package static func distance(_ a: SpacingPreference, _ b: SpacingPreference) -> CGFloat {
        switch (a.kind, b.kind) {
        case (.standard, .standard): return max(a.towardStandard, b.towardStandard)
        case (.standard, _): return b.towardStandard
        case (_, .standard): return a.towardStandard
        default: return min(a.towardText, b.towardText)
        }
    }
}

public struct ViewSpacing: Sendable {
    package var top: [SpacingPreference]
    package var leading: [SpacingPreference]
    package var bottom: [SpacingPreference]
    package var trailing: [SpacingPreference]

    package init(top: [SpacingPreference], leading: [SpacingPreference],
                 bottom: [SpacingPreference], trailing: [SpacingPreference]) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = ViewSpacing(top: [], leading: [], bottom: [], trailing: [])

    public init() {
        self.init(top: [.standard], leading: [.standard], bottom: [.standard], trailing: [.standard])
    }

    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) {
        func merge(_ a: inout [SpacingPreference], _ b: [SpacingPreference]) {
            for p in b where !a.contains(p) { a.append(p) }
        }
        if edges.contains(.top) { merge(&top, other.top) }
        if edges.contains(.leading) { merge(&leading, other.leading) }
        if edges.contains(.bottom) { merge(&bottom, other.bottom) }
        if edges.contains(.trailing) { merge(&trailing, other.trailing) }
    }

    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
        var r = self
        r.formUnion(other, edges: edges)
        return r
    }

    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat {
        let a = axis == .horizontal ? trailing : bottom
        let b = axis == .horizontal ? next.leading : next.top
        var best: CGFloat?
        for p in a {
            for q in b {
                let d = SpacingPreference.distance(p, q)
                best = max(best ?? d, d)
            }
        }
        return best ?? 0
    }

    package func replacing(_ edges: Edge.Set, with preferences: [SpacingPreference]) -> ViewSpacing {
        var r = self
        if edges.contains(.top) { r.top = preferences }
        if edges.contains(.leading) { r.leading = preferences }
        if edges.contains(.bottom) { r.bottom = preferences }
        if edges.contains(.trailing) { r.trailing = preferences }
        return r
    }
}
