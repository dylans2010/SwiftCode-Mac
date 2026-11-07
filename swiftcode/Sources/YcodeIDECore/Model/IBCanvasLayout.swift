#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public struct IBCanvasLayout {
    public struct Placement {
        public var view: IBDocument.Object
        public var scene: IBDocument.Object
        public var title: String
        public var origin: CGPoint
        public var titleBar: CGFloat
        public var box: CGRect { CGRect(origin: origin, size: view.frame?.size ?? .zero) }
        public var full: CGRect { CGRect(x: origin.x, y: origin.y - titleBar, width: box.width, height: box.height + titleBar) }
    }

    public enum Handle: CaseIterable, Sendable { case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }

    public static let sceneBarHeight: CGFloat = 24
    public static let margin: CGFloat = 200
    public static let windowTitleBar: CGFloat = 28
    public var sceneBarGap: CGFloat { document.isFlippedRuntime ? 16 : 6 }

    public let document: IBDocument
    public private(set) var placements: [Placement] = []
    public private(set) var contentBounds: CGRect = .zero
    public var canvasSize: CGSize { CGSize(width: contentBounds.maxX + Self.margin, height: contentBounds.maxY + Self.margin) }

    public init(document: IBDocument) {
        self.document = document
        var nextX: CGFloat = 0
        var boxes: [CGRect] = []
        for r in document.roots {
            var views: [(IBDocument.Object, CGFloat)] = []
            func collect(_ o: IBDocument.Object) {
                if o.isView { views.append((o, o.parent?.contentRect != nil ? Self.windowTitleBar : 0)); return }
                o.children.forEach(collect)
            }
            collect(r)
            for (v, bar) in views {
                let size = CGSize(width: v.frame?.width ?? 0, height: (v.frame?.height ?? 0) + bar)
                let origin: CGPoint
                if let c = r.canvasLocation, views.count == 1 {
                    origin = CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2)
                } else {
                    origin = CGPoint(x: nextX, y: 0)
                }
                nextX = max(nextX, origin.x + size.width + 80)
                let title = r.element == "scene" ? (r.children.first?.displayName ?? r.displayName) : (v.parent?.displayName ?? v.displayName)
                placements.append(Placement(view: v, scene: r, title: title, origin: CGPoint(x: origin.x, y: origin.y + bar), titleBar: bar))
                boxes.append(CGRect(origin: origin, size: size))
            }
        }
        let union = boxes.reduce(boxes.first ?? .zero) { $0.union($1) }
        let dx = Self.margin - union.minX, dy = Self.margin - union.minY
        for i in placements.indices { placements[i].origin.x += dx; placements[i].origin.y += dy }
        contentBounds = union.offsetBy(dx: dx, dy: dy)
    }

    public func placement(of o: IBDocument.Object) -> Placement? {
        guard let root = document.rootView(of: o) else { return nil }
        return placements.first { $0.view.id == root.id }
    }

    public func rect(of o: IBDocument.Object) -> CGRect? {
        guard let p = placement(of: o), let f = document.frameInRoot(o) else { return nil }
        return f.offsetBy(dx: p.origin.x, dy: p.origin.y)
    }

    public func sceneBox(_ scene: IBDocument.Object) -> CGRect? {
        placements.first { $0.scene === scene }?.full
    }

    public func sceneBar(_ p: Placement) -> CGRect {
        CGRect(x: p.full.minX, y: p.full.minY - Self.sceneBarHeight - sceneBarGap, width: p.full.width, height: Self.sceneBarHeight)
    }

    public func scene(containing id: String) -> IBDocument.Object? {
        var o = document.byID[id]
        while let c = o, c.parent != nil { o = c.parent }
        return o
    }

    public func view(at p: CGPoint) -> IBDocument.Object? {
        var hit: IBDocument.Object?
        for pl in placements { pl.view.walk { v in if v.isView, let r = rect(of: v), r.contains(p) { hit = v } } }
        return hit
    }

    public func sceneBar(at p: CGPoint) -> Placement? { placements.first { sceneBar($0).contains(p) } }

    public var segueLines: [(from: CGPoint, to: CGPoint, kind: String)] {
        var out: [(CGPoint, CGPoint, String)] = []
        for r in document.roots {
            r.walk { o in
                for c in o.connections where c.kind == .segue {
                    guard let s = scene(containing: o.id), let d = scene(containing: c.other), s !== d,
                          let a = sceneBox(s), let b = sceneBox(d) else { continue }
                    out.append((CGPoint(x: a.maxX, y: a.midY), CGPoint(x: b.minX, y: b.midY), c.name))
                }
            }
        }
        return out
    }

    public var entryPoint: (from: CGPoint, to: CGPoint)? {
        guard let id = document.initialViewController, let s = scene(containing: id), let b = sceneBox(s) else { return nil }
        return (CGPoint(x: b.minX - 70, y: b.midY), CGPoint(x: b.minX - 4, y: b.midY))
    }

    public static func handles(_ r: CGRect) -> [(handle: Handle, rect: CGRect)] {
        let pts: [(Handle, CGPoint)] = [(.topLeft, CGPoint(x: r.minX, y: r.minY)), (.top, CGPoint(x: r.midX, y: r.minY)),
                                        (.topRight, CGPoint(x: r.maxX, y: r.minY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
                                        (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)), (.bottom, CGPoint(x: r.midX, y: r.maxY)),
                                        (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.left, CGPoint(x: r.minX, y: r.midY))]
        return pts.map { ($0.0, CGRect(x: $0.1.x - 4, y: $0.1.y - 4, width: 8, height: 8)) }
    }

    public static func dragged(_ r: CGRect, handle: Handle?, by d: CGSize) -> CGRect {
        var x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY
        switch handle {
        case nil: x0 += d.width; x1 += d.width; y0 += d.height; y1 += d.height
        case .topLeft?: x0 += d.width; y0 += d.height
        case .top?: y0 += d.height
        case .topRight?: x1 += d.width; y0 += d.height
        case .right?: x1 += d.width
        case .bottomRight?: x1 += d.width; y1 += d.height
        case .bottom?: y1 += d.height
        case .bottomLeft?: x0 += d.width; y1 += d.height
        case .left?: x0 += d.width
        }
        return CGRect(x: min(x0, x1).rounded(), y: min(y0, y1).rounded(), width: abs(x1 - x0).rounded(), height: abs(y1 - y0).rounded())
    }

    public func constraintGuides(for o: IBDocument.Object) -> [(id: String, from: CGPoint, to: CGPoint)] {
        func point(_ r: CGRect, _ a: String) -> CGPoint {
            switch a {
            case "leading", "left", "leadingMargin": return CGPoint(x: r.minX, y: r.midY)
            case "trailing", "right", "trailingMargin": return CGPoint(x: r.maxX, y: r.midY)
            case "top", "topMargin": return CGPoint(x: r.midX, y: r.minY)
            case "bottom", "bottomMargin", "baseline", "lastBaseline": return CGPoint(x: r.midX, y: r.maxY)
            default: return CGPoint(x: r.midX, y: r.midY)
            }
        }
        var out: [(String, CGPoint, CGPoint)] = []
        for c in document.constraints(involving: o.id) {
            guard let a = c.firstItem.flatMap({ document.byID[$0] }).flatMap({ rect(of: $0) }) else { continue }
            let p1 = point(a, c.firstAttribute)
            if let second = c.secondItem.flatMap({ document.byID[$0] }), let b = rect(of: second) {
                out.append((c.id, p1, point(b, c.secondAttribute ?? c.firstAttribute)))
            } else {
                let w = c.firstAttribute == "width"
                out.append((c.id, w ? CGPoint(x: a.minX, y: a.maxY + 6) : CGPoint(x: a.maxX + 6, y: a.minY),
                            w ? CGPoint(x: a.maxX, y: a.maxY + 6) : CGPoint(x: a.maxX + 6, y: a.maxY)))
            }
        }
        return out
    }

    public var fitBounds: CGRect {
        guard !placements.isEmpty else { return contentBounds }
        let bezel: CGFloat = document.isFlippedRuntime ? 12 : 0
        let top = Self.sceneBarHeight + sceneBarGap
        return CGRect(x: contentBounds.minX - bezel, y: contentBounds.minY - top, width: contentBounds.width + 2 * bezel,
                      height: contentBounds.height + top + bezel)
    }

    public func zoomToFit(_ viewport: CGSize) -> CGFloat {
        let content = fitBounds.insetBy(dx: -20, dy: -20)
        guard content.width > 0, content.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        return Self.clampZoom(min(viewport.width / content.width, viewport.height / content.height, 1))
    }

    public static func clampZoom(_ z: CGFloat) -> CGFloat { min(max(z, 0.1), 4) }

    public func sceneObjects(_ scene: IBDocument.Object) -> [IBDocument.Object] {
        scene.element == "scene" ? document.outlineChildren(scene) : []
    }

    public func sceneBarIcons(_ p: Placement, selected: String?) -> [(id: String, rect: CGRect, symbol: String)] {
        let objects = sceneObjects(p.scene)
        guard let sel = selected, p.scene.id == sel || objects.contains(where: { $0.id == sel }) else { return [] }
        let bar = sceneBar(p)
        return objects.reversed().enumerated().map { i, o in
            let symbol = o.element == "exit" ? "rectangle.portrait.and.arrow.right"
                : (o.element.hasSuffix("Controller") || o.attribute("sceneMemberID") == "viewController") ? "square.dashed" : "cube"
            return (o.id, CGRect(x: bar.maxX - 20 - CGFloat(i) * 18, y: bar.minY + 5, width: 14, height: 14), symbol)
        }.reversed()
    }

    public func overview(in size: CGSize) -> (scale: CGFloat, boxes: [CGRect]) {
        let inner = CGSize(width: size.width - 16, height: size.height - 16)
        guard contentBounds.width > 0, contentBounds.height > 0, inner.width > 0, inner.height > 0 else { return (0, []) }
        let k = min(inner.width / contentBounds.width, inner.height / contentBounds.height)
        let ox = 8 + (inner.width - contentBounds.width * k) / 2, oy = 8 + (inner.height - contentBounds.height * k) / 2
        let boxes = placements.map { p in
            CGRect(x: ox + (p.full.minX - contentBounds.minX) * k, y: oy + (p.full.minY - contentBounds.minY) * k, width: p.full.width * k, height: p.full.height * k)
        }
        return (k, boxes)
    }

    public func overviewRect(_ r: CGRect, in size: CGSize) -> CGRect {
        let (k, _) = overview(in: size)
        let inner = CGSize(width: size.width - 16, height: size.height - 16)
        let ox = 8 + (inner.width - contentBounds.width * k) / 2, oy = 8 + (inner.height - contentBounds.height * k) / 2
        return CGRect(x: ox + (r.minX - contentBounds.minX) * k, y: oy + (r.minY - contentBounds.minY) * k, width: r.width * k, height: r.height * k)
    }
}

public struct IBCanvasDrag {
    public var id: String
    public var handle: IBCanvasLayout.Handle?
    public var start: CGPoint
    public var original: CGRect
    public var root: CGRect

    public static func begin(at p: CGPoint, selected: String?, in layout: IBCanvasLayout) -> (hit: IBDocument.Object?, drag: IBCanvasDrag?) {
        let d = layout.document
        if let id = selected, let o = d.byID[id], o.parent?.isView == true, let r = layout.rect(of: o), let root = d.frameInRoot(o),
           let h = IBCanvasLayout.handles(r).first(where: { $0.rect.insetBy(dx: -2, dy: -2).contains(p) }) {
            return (o, IBCanvasDrag(id: id, handle: h.handle, start: p, original: r, root: root))
        }
        guard let v = layout.view(at: p) else { return (nil, nil) }
        guard v.parent?.isView == true, let r = layout.rect(of: v), let root = d.frameInRoot(v) else { return (v, nil) }
        return (v, IBCanvasDrag(id: v.id, handle: nil, start: p, original: r, root: root))
    }

    public func preview(at p: CGPoint) -> CGRect {
        IBCanvasLayout.dragged(original, handle: handle, by: CGSize(width: p.x - start.x, height: p.y - start.y))
    }

    public func result(at p: CGPoint) -> CGRect? {
        let delta = CGSize(width: p.x - start.x, height: p.y - start.y)
        guard delta.width != 0 || delta.height != 0 else { return nil }
        return IBCanvasLayout.dragged(root, handle: handle, by: delta)
    }
}
