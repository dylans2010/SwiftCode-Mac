import Foundation

package struct ChildPlacement {
    package var index: Int
    package var origin: CGPoint
    package var size: CGSize
    package var proposal: ProposedViewSize

    package init(index: Int, origin: CGPoint, size: CGSize, proposal: ProposedViewSize) {
        self.index = index
        self.origin = origin
        self.size = size
        self.proposal = proposal
    }
}

package protocol NodeBehavior {
    func childStackOrientation(inherited: Axis?, child index: Int) -> Axis?
    func sizeThatFits(_ proposal: ProposedViewSize, node: LayoutNode) -> CGSize
    func placeChildren(size: CGSize, proposal: ProposedViewSize, node: LayoutNode) -> [ChildPlacement]
    func explicitAlignment(_ key: AlignmentKey, size: CGSize, proposal: ProposedViewSize, node: LayoutNode) -> CGFloat?
    func spacing(node: LayoutNode) -> ViewSpacing
    func layoutPriority(node: LayoutNode) -> Double
    func layoutValue(_ key: ObjectIdentifier, node: LayoutNode) -> Any?
    func childTransform(size: CGSize) -> AffineTransform2D?
    var traitChild: Int? { get }
    var isEmpty: Bool { get }
}

extension NodeBehavior {
    package var traitChild: Int? { nil }
    package var isEmpty: Bool { false }

    package func childStackOrientation(inherited: Axis?, child index: Int) -> Axis? {
        traitChild == index ? inherited : nil
    }

    package func placeChildren(size: CGSize, proposal: ProposedViewSize, node: LayoutNode) -> [ChildPlacement] { [] }

    package func explicitAlignment(_ key: AlignmentKey, size: CGSize, proposal: ProposedViewSize,
                                   node: LayoutNode) -> CGFloat? {
        guard let i = traitChild else { return nil }
        return node.childExplicitAlignment(key, child: i, size: size, proposal: proposal)
    }

    package func spacing(node: LayoutNode) -> ViewSpacing {
        traitChild.map { node.children[$0].spacing } ?? ViewSpacing()
    }

    package func layoutPriority(node: LayoutNode) -> Double {
        traitChild.map { node.children[$0].layoutPriority } ?? 0
    }

    package func layoutValue(_ key: ObjectIdentifier, node: LayoutNode) -> Any? {
        traitChild.flatMap { node.children[$0].layoutValue(key) }
    }

    package func childTransform(size: CGSize) -> AffineTransform2D? { nil }
}

package final class LayoutContext {
    package var environment: EnvironmentValues
    package var textMeasurer: any TextMeasurer
    package var symbols: any SymbolProvider
    package var safeArea: (window: CGRect, safe: CGRect)?
    package private(set) var uncertainCount = 0
    private var interest: Axis.Set = [.horizontal, .vertical]
    fileprivate var unknownAccumulator: Axis.Set = []

    package init(environment: EnvironmentValues = EnvironmentValues(),
                 textMeasurer: any TextMeasurer = TypesetTextMeasurer.shared,
                 symbols: any SymbolProvider = StubSymbolProvider()) {
        self.environment = environment
        self.textMeasurer = textMeasurer
        self.symbols = symbols
    }

    package func uncertain(_ axes: Axis.Set) {
        guard !axes.isEmpty else { return }
        unknownAccumulator.formUnion(axes)
        if !axes.isDisjoint(with: interest) { uncertainCount += 1 }
    }

    package func measuring<R>(_ axis: Axis, _ body: () -> R) -> R {
        let saved = interest, outer = unknownAccumulator
        interest = Axis.Set(axis)
        unknownAccumulator = []
        let r = body()
        unknownAccumulator = outer.union(unknownAccumulator.intersection(Axis.Set(axis)))
        interest = saved
        return r
    }
}

package final class LayoutNode {
    package let behavior: any NodeBehavior
    package private(set) var children: [LayoutNode]
    package var name: String?
    package private(set) var stackOrientation: Axis?
    package private(set) var context: LayoutContext!

    package var layoutCache: Any?

    package weak var owner: AnyObject?

    package weak var creator: AnyObject?
    package var creatorIndex = 0

    package var presentation: PresentationEffect?

    package var draw: NodeDraw?
    package var renderEffects: [NodeRenderEffect] = []

    private var sizes: [ProposalKey: (size: CGSize, unknown: Axis.Set)] = [:]
    private var dims: [ProposalKey: ViewDimensions] = [:]
    private var placementMemo: [PlacementKey: [ChildPlacement]] = [:]

    package private(set) var placedFrame: CGRect?
    package private(set) var placedSize: CGSize?
    package private(set) var placedProposal: ProposedViewSize?
    package private(set) var placedTransform: AffineTransform2D?
    package private(set) var placedLocalOrigin: CGPoint?

    package init(_ behavior: any NodeBehavior, children: [LayoutNode] = [], name: String? = nil) {
        self.behavior = behavior
        self.children = children
        self.name = name
    }

    package var layoutChildren: [LayoutNode] { children.filter { !$0.behavior.isEmpty } }

    package func prepare(context: LayoutContext, stackOrientation: Axis? = nil) {
        self.context = context
        self.stackOrientation = stackOrientation
        sizes = [:]
        dims = [:]
        placementMemo = [:]
        layoutCache = nil
        placedFrame = nil
        placedSize = nil
        placedProposal = nil
        placedTransform = nil
        placedLocalOrigin = nil
        for (i, c) in children.enumerated() {
            c.prepare(context: context,
                      stackOrientation: behavior.childStackOrientation(inherited: stackOrientation, child: i))
        }
    }

    package func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let key = ProposalKey(proposal)
        if let s = sizes[key] {
            context.uncertain(s.unknown)
            return s.size
        }
        let outer = context.unknownAccumulator
        context.unknownAccumulator = []
        let s = behavior.sizeThatFits(proposal, node: self)
        let unknown = context.unknownAccumulator
        sizes[key] = (s, unknown)
        context.unknownAccumulator = outer.union(unknown)
        return s
    }

    package func length(along axis: Axis, _ proposal: ProposedViewSize) -> CGFloat {
        context.measuring(axis) { sizeThatFits(proposal)[axis] }
    }

    package func dimensions(_ proposal: ProposedViewSize) -> ViewDimensions {
        let key = ProposalKey(proposal)
        if let d = dims[key] { return d }
        let size = sizeThatFits(proposal)
        let d = ViewDimensions(size: size, guides: ExplicitGuides { [unowned self] k in
            self.behavior.explicitAlignment(k, size: size, proposal: proposal, node: self)
        })
        dims[key] = d
        return d
    }

    package var spacing: ViewSpacing { behavior.spacing(node: self) }
    package var layoutPriority: Double { behavior.layoutPriority(node: self) }
    package func layoutValue(_ key: ObjectIdentifier) -> Any? { behavior.layoutValue(key, node: self) }

    package func placements(size: CGSize, proposal: ProposedViewSize) -> [ChildPlacement] {
        let key = PlacementKey(size: size, proposal: proposal)
        if let p = placementMemo[key] { return p }
        let p = behavior.placeChildren(size: size, proposal: proposal, node: self)
        placementMemo[key] = p
        return p
    }

    package func childExplicitAlignment(_ key: AlignmentKey, child index: Int, size: CGSize,
                                        proposal: ProposedViewSize) -> CGFloat? {
        guard let pl = placements(size: size, proposal: proposal).first(where: { $0.index == index }),
              let v = children[index].dimensions(pl.proposal).explicitValue(key) else { return nil }
        return pl.origin[key.axis] + v
    }

    package func place(at origin: CGPoint, size: CGSize, proposal: ProposedViewSize,
                       parentTransform: AffineTransform2D = .identity) {
        let t = parentTransform.concatenating(.translation(origin.x, origin.y))
        placedTransform = t
        placedLocalOrigin = origin
        placedSize = size
        placedProposal = proposal
        placedFrame = t.boundingBox(of: CGRect(origin: .zero, size: size))
        let childT = behavior.childTransform(size: size).map { t.concatenating($0) } ?? t
        var pls = placements(size: size, proposal: proposal)
        if let expanding = behavior as? any SafeAreaExpandingBehavior {
            pls = expanding.expand(pls, node: self, frame: placedFrame!)
        }
        for pl in pls {
            children[pl.index].place(at: pl.origin, size: pl.size, proposal: pl.proposal, parentTransform: childT)
        }
    }

    package func forEachNode(_ body: (LayoutNode) -> Void) {
        body(self)
        for c in children { c.forEachNode(body) }
    }
}

package enum PresentationEffect {
    case opacity(@MainActor () -> Double)
    case transform(@MainActor (CGSize) -> AffineTransform2D)
}

private struct PlacementKey: Hashable {
    let w: Double, h: Double
    let p: ProposalKey
    init(size: CGSize, proposal: ProposedViewSize) {
        w = Double(size.width)
        h = Double(size.height)
        p = ProposalKey(proposal)
    }
}

package protocol SafeAreaExpandingBehavior: NodeBehavior {
    func expand(_ placements: [ChildPlacement], node: LayoutNode, frame: CGRect) -> [ChildPlacement]
}

package struct AffineTransform2D: Equatable {
    package var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

    package static let identity = AffineTransform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    package static func translation(_ x: CGFloat, _ y: CGFloat) -> AffineTransform2D {
        AffineTransform2D(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    package static func scale(_ sx: CGFloat, _ sy: CGFloat) -> AffineTransform2D {
        AffineTransform2D(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    package static func rotation(_ radians: Double) -> AffineTransform2D {
        let (s, c) = (CGFloat(sin(radians)), CGFloat(cos(radians)))
        return AffineTransform2D(a: c, b: s, c: -s, d: c, tx: 0, ty: 0)
    }

    package func concatenating(_ o: AffineTransform2D) -> AffineTransform2D {
        AffineTransform2D(a: a * o.a + c * o.b, b: b * o.a + d * o.b,
                          c: a * o.c + c * o.d, d: b * o.c + d * o.d,
                          tx: a * o.tx + c * o.ty + tx, ty: b * o.tx + d * o.ty + ty)
    }

    package func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty)
    }

    package func about(_ anchor: CGPoint) -> AffineTransform2D {
        AffineTransform2D.translation(anchor.x, anchor.y).concatenating(self)
            .concatenating(.translation(-anchor.x, -anchor.y))
    }

    package func boundingBox(of r: CGRect) -> CGRect {
        if b == 0 && c == 0 {
            let x0 = a * r.minX + tx, x1 = a * r.maxX + tx
            let y0 = d * r.minY + ty, y1 = d * r.maxY + ty
            return CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
        }
        let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                   CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)].map(apply)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
