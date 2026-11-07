import Foundation

package struct LayoutEngine {
    package var environment: EnvironmentValues
    package var textMeasurer: any TextMeasurer
    package var symbols: any SymbolProvider

    package init(environment: EnvironmentValues = EnvironmentValues(),
                 textMeasurer: any TextMeasurer = TypesetTextMeasurer.shared,
                 symbols: any SymbolProvider = StubSymbolProvider()) {
        self.environment = environment
        self.textMeasurer = textMeasurer
        self.symbols = symbols
    }

    @discardableResult
    package func prepare(_ root: LayoutNode) -> LayoutContext {
        let ctx = LayoutContext(environment: environment, textMeasurer: textMeasurer, symbols: symbols)
        root.prepare(context: ctx)
        return ctx
    }

    package func sizeThatFits(_ root: LayoutNode, _ proposal: ProposedViewSize) -> (size: CGSize, exact: Bool) {
        let ctx = prepare(root)
        let s = root.sizeThatFits(proposal)
        return (s, ctx.uncertainCount == 0)
    }

    package func layout(_ root: LayoutNode, proposal: ProposedViewSize) -> LayoutResult {
        let ctx = prepare(root)
        let size = root.sizeThatFits(proposal)
        root.place(at: .zero, size: size, proposal: proposal)
        return LayoutResult(root: root, context: ctx, size: size, proposal: proposal,
                            mirrorWidth: environment.layoutDirection == .rightToLeft ? size.width : nil)
    }

    package func layout(_ root: LayoutNode, window: CGSize, safeAreaInsets insets: EdgeInsets) -> LayoutResult {
        let ctx = prepare(root)
        let windowRect = CGRect(origin: .zero, size: window)
        let safe = CGRect(x: insets.leading, y: insets.top,
                          width: Swift.max(window.width - insets.horizontal, 0),
                          height: Swift.max(window.height - insets.vertical, 0))
        ctx.safeArea = (windowRect, safe)
        let proposal = ProposedViewSize(safe.size)
        let size = root.sizeThatFits(proposal)
        let origin = CGPoint(x: safe.minX + (safe.width - size.width) / 2, y: safe.minY + (safe.height - size.height) / 2)
        root.place(at: origin, size: size, proposal: proposal)
        return LayoutResult(root: root, context: ctx, size: size, proposal: proposal,
                            mirrorWidth: environment.layoutDirection == .rightToLeft ? window.width : nil)
    }
}

package struct LayoutResult {
    package let root: LayoutNode
    package let context: LayoutContext
    package let size: CGSize
    package let proposal: ProposedViewSize
    package let mirrorWidth: CGFloat?

    package var baselines: (first: CGFloat, last: CGFloat) {
        let d = root.dimensions(proposal)
        return (d[VerticalAlignment.firstTextBaseline], d[VerticalAlignment.lastTextBaseline])
    }

    package var isExact: Bool { context.uncertainCount == 0 }

    package func frame(of node: LayoutNode) -> CGRect? {
        guard var f = node.placedFrame else { return nil }
        if let w = mirrorWidth { f.origin.x = w - f.origin.x - f.width }
        return f
    }

    package var namedFrames: [String: CGRect] {
        var r: [String: CGRect] = [:]
        root.forEachNode { n in
            if let name = n.name, let f = frame(of: n) { r[name] = f }
        }
        return r
    }

    package func node(named name: String) -> LayoutNode? {
        var found: LayoutNode?
        root.forEachNode { if found == nil && $0.name == name { found = $0 } }
        return found
    }

    package func safeAreaInsets(of node: LayoutNode) -> EdgeInsets {
        guard let area = context.safeArea, let f = node.placedFrame else { return EdgeInsets() }
        let eps: CGFloat = 0.001
        var r = EdgeInsets()
        if f.minY <= area.safe.minY + eps { r.top = area.safe.minY - area.window.minY }
        if f.minX <= area.safe.minX + eps { r.leading = area.safe.minX - area.window.minX }
        if f.maxY >= area.safe.maxY - eps { r.bottom = area.window.maxY - area.safe.maxY }
        if f.maxX >= area.safe.maxX - eps { r.trailing = area.window.maxX - area.safe.maxX }
        return r
    }
}
