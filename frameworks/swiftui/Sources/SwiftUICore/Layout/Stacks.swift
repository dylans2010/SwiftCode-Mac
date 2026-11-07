import Foundation

package struct DistributionItem {
    package var minLength: CGFloat
    package var maxLength: CGFloat
    package var priority: Double
    package var measure: (CGFloat) -> CGFloat

    package init(minLength: CGFloat, maxLength: CGFloat, priority: Double, measure: @escaping (CGFloat) -> CGFloat) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.priority = priority
        self.measure = measure
    }
}

package func distribute(_ available: CGFloat, _ items: [DistributionItem]) -> [(offer: CGFloat, length: CGFloat)] {
    var result = Array(repeating: (offer: CGFloat(0), length: CGFloat(0)), count: items.count)
    func minus(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a.isInfinite ? a : a - b }
    var remaining = available
    let priorities = Set(items.map(\.priority)).sorted(by: >)
    for prio in priorities {
        let members = items.indices.filter { items[$0].priority == prio }
        let reserved = items.indices.filter { items[$0].priority < prio }.reduce(CGFloat(0)) { $0 + items[$1].minLength }
        var left = minus(remaining, reserved)
        let ordered = members.sorted { a, b in
            let fa = items[a].maxLength - items[a].minLength, fb = items[b].maxLength - items[b].minLength
            if fa != fb && !(fa.isInfinite && fb.isInfinite) { return fa < fb }
            if items[a].minLength != items[b].minLength { return items[a].minLength > items[b].minLength }
            return a < b
        }
        var count = ordered.count
        var used: CGFloat = 0
        for i in ordered {
            let offer = Swift.max(0, left / CGFloat(count))
            let length = items[i].measure(offer)
            result[i] = (offer, length)
            left = minus(left, length)
            used += length
            count -= 1
        }
        remaining = minus(remaining, used)
    }
    return result
}

package func alignedExtent(_ dims: [ViewDimensions], _ key: AlignmentKey, _ axis: Axis) -> (positions: [CGFloat], extent: CGFloat) {
    guard !dims.isEmpty else { return ([], 0) }
    if dims.contains(where: { $0.size[axis].isInfinite }) {
        return (dims.map { _ in 0 }, .infinity)
    }
    let guides = dims.map { $0[key: key] }
    let before = max(guides.max()!, 0)
    let after = max(zip(guides, dims).map { g, d in d.size[axis] - g }.max()!, 0)
    return (guides.map { before - $0 }, before + after)
}

package struct StackAlgorithm {
    package var axis: Axis
    package var alignmentKey: AlignmentKey
    package var spacing: CGFloat?

    package struct Arrangement {
        var proposals: [ProposedViewSize]
        var dimensions: [ViewDimensions]
        var along: [CGFloat]
        var across: [CGFloat]
        var size: CGSize
    }

    package func gaps(_ subviews: LayoutSubviews) -> [CGFloat] {
        guard subviews.count > 1 else { return [] }
        let svs = Array(subviews)
        return (0..<(svs.count - 1)).map { i in
            spacing ?? svs[i].spacing.distance(to: svs[i + 1].spacing, along: axis)
        }
    }

    package func arrange(_ p: ProposedViewSize, _ subviews: LayoutSubviews) -> Arrangement {
        let svs = Array(subviews)
        let gaps = gaps(subviews)
        let totalGap = gaps.reduce(0, +)
        let across = p[axis.otherAxis]
        var proposals: [ProposedViewSize]
        if let along = p[axis] {
            let items = svs.map { sv in
                DistributionItem(
                    minLength: sv.node.length(along: axis, ProposedViewSize(axis, along: 0, across: across)),
                    maxLength: sv.node.length(along: axis, ProposedViewSize(axis, along: .infinity, across: across)),
                    priority: sv.priority,
                    measure: { sv.node.length(along: axis, ProposedViewSize(axis, along: $0, across: across)) })
            }
            let d = distribute(along - totalGap, items)
            proposals = d.map { ProposedViewSize(axis, along: $0.offer, across: across) }
        } else {
            proposals = svs.map { _ in ProposedViewSize(axis, along: nil, across: across) }
        }
        let dims = zip(svs, proposals).map { $0.dimensions(in: $1) }
        var pos: [CGFloat] = []
        var cursor: CGFloat = 0
        for (i, d) in dims.enumerated() {
            pos.append(cursor)
            cursor += d.size[axis] + (i < gaps.count ? gaps[i] : 0)
        }
        let (crossPos, extent) = alignedExtent(dims, alignmentKey, axis.otherAxis)
        return Arrangement(proposals: proposals, dimensions: dims, along: pos, across: crossPos,
                           size: CGSize(axis, along: svs.isEmpty ? 0 : cursor, across: extent))
    }

    package func place(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews) {
        let a = arrange(proposal, subviews)
        let slack = bounds.size[axis.otherAxis] - a.size[axis.otherAxis]
        let unit = Swift.min(Swift.max(alignmentKey.defaultValue(for: CGSize(width: 1, height: 1)), 0), 1)
        let crossStart = bounds.origin[axis.otherAxis] + (abs(slack) < 0.001 ? 0 : slack * unit)
        for (i, sv) in subviews.enumerated() {
            let pt = CGPoint(axis, along: bounds.origin[axis] + a.along[i], across: crossStart + a.across[i])
            sv.place(at: pt, anchor: .topLeading, proposal: a.proposals[i])
        }
    }

    package func spacing(_ subviews: LayoutSubviews) -> ViewSpacing {
        var s = ViewSpacing.zero
        let svs = Array(subviews)
        let (startEdge, endEdge): (Edge.Set, Edge.Set) = axis == .horizontal ? (.leading, .trailing) : (.top, .bottom)
        let sides: Edge.Set = axis == .horizontal ? .vertical : .horizontal
        for (i, sv) in svs.enumerated() {
            var edges = sides
            if i == 0 { edges.formUnion(startEdge) }
            if i == svs.count - 1 { edges.formUnion(endEdge) }
            s.formUnion(sv.spacing, edges: edges)
        }
        return s
    }
}

public struct HStackLayout: Layout {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public typealias Cache = Void
    public typealias AnimatableData = EmptyAnimatableData

    public static var layoutProperties: LayoutProperties {
        var p = LayoutProperties()
        p.stackOrientation = .horizontal
        return p
    }

    private var algorithm: StackAlgorithm { StackAlgorithm(axis: .horizontal, alignmentKey: alignment.key, spacing: spacing) }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        algorithm.arrange(proposal, subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        algorithm.place(in: bounds, proposal: proposal, subviews: subviews)
    }

    public func spacing(subviews: Subviews, cache: inout Void) -> ViewSpacing { algorithm.spacing(subviews) }
}

public struct VStackLayout: Layout {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public typealias Cache = Void
    public typealias AnimatableData = EmptyAnimatableData

    public static var layoutProperties: LayoutProperties {
        var p = LayoutProperties()
        p.stackOrientation = .vertical
        return p
    }

    private var algorithm: StackAlgorithm { StackAlgorithm(axis: .vertical, alignmentKey: alignment.key, spacing: spacing) }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        algorithm.arrange(proposal, subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        algorithm.place(in: bounds, proposal: proposal, subviews: subviews)
    }

    public func spacing(subviews: Subviews, cache: inout Void) -> ViewSpacing { algorithm.spacing(subviews) }
}

public struct ZStackLayout: Layout {
    public var alignment: Alignment

    public init(alignment: Alignment = .center) { self.alignment = alignment }

    public typealias Cache = Void
    public typealias AnimatableData = EmptyAnimatableData

    private struct Arrangement {
        var origins: [CGPoint]
        var size: CGSize
    }

    private func arrange(_ p: ProposedViewSize, _ subviews: Subviews) -> Arrangement {
        let dims = subviews.map { $0.dimensions(in: p) }
        guard !dims.isEmpty else { return Arrangement(origins: [], size: .zero) }
        let (xs, w) = alignedExtent(dims, alignment.horizontal.key, .horizontal)
        let (ys, h) = alignedExtent(dims, alignment.vertical.key, .vertical)
        return Arrangement(origins: zip(xs, ys).map { CGPoint(x: $0, y: $1) }, size: CGSize(width: w, height: h))
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        arrange(proposal, subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let a = arrange(proposal, subviews)
        let ux = Swift.min(Swift.max(alignment.horizontal.key.defaultValue(for: CGSize(width: 1, height: 1)), 0), 1)
        let uy = Swift.min(Swift.max(alignment.vertical.key.defaultValue(for: CGSize(width: 1, height: 1)), 0), 1)
        let dx = abs(bounds.width - a.size.width) < 0.001 ? 0 : (bounds.width - a.size.width) * ux
        let dy = abs(bounds.height - a.size.height) < 0.001 ? 0 : (bounds.height - a.size.height) * uy
        for (i, sv) in subviews.enumerated() {
            sv.place(at: CGPoint(x: bounds.minX + dx + a.origins[i].x, y: bounds.minY + dy + a.origins[i].y),
                     anchor: .topLeading, proposal: proposal)
        }
    }
}
