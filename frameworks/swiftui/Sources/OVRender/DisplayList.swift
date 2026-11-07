import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct DisplayItemID: Hashable, Sendable, CustomStringConvertible {
    public var raw: UInt64
    public init(_ raw: UInt64) { self.raw = raw }

    public func child(_ discriminator: UInt64) -> DisplayItemID {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for v in [raw, discriminator] {
            var x = v
            for _ in 0..<8 {
                h ^= x & 0xff
                h = h &* 0x0000_0100_0000_01b3
                x >>= 8
            }
        }
        return DisplayItemID(h)
    }

    public func child(_ name: String) -> DisplayItemID {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in name.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return child(h)
    }

    public static let root = DisplayItemID(0x6f76_7230_7430_6f74)
    public var description: String { "#" + String(raw, radix: 16) }
}

public struct RenderColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    public static let clear = RenderColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let black = RenderColor(red: 0, green: 0, blue: 0)
    public static let white = RenderColor(red: 1, green: 1, blue: 1)

    public func withAlpha(_ a: Double) -> RenderColor {
        RenderColor(red: red, green: green, blue: blue, alpha: alpha * a)
    }

    public var rgba8: (UInt8, UInt8, UInt8, UInt8) {
        func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return (q(red), q(green), q(blue), q(alpha))
    }
}

public struct RenderGradientStop: Hashable, Sendable {
    public var color: RenderColor
    public var location: Double
    public init(color: RenderColor, location: Double) {
        self.color = color
        self.location = location
    }
}

public enum RenderSpread: Hashable, Sendable {
    case pad, `repeat`, reflect
}

public enum RenderPaint: Equatable, Sendable {
    case color(RenderColor)
    case linearGradient(stops: [RenderGradientStop], start: CGPoint, end: CGPoint, spread: RenderSpread)
    case radialGradient(stops: [RenderGradientStop], center: CGPoint, startRadius: Double, endRadius: Double, spread: RenderSpread)
    case conicGradient(stops: [RenderGradientStop], center: CGPoint, startAngle: Double, endAngle: Double)

    public func multiplyingOpacity(_ opacity: Double) -> RenderPaint {
        if opacity == 1 { return self }
        func m(_ s: [RenderGradientStop]) -> [RenderGradientStop] {
            s.map { RenderGradientStop(color: $0.color.withAlpha(opacity), location: $0.location) }
        }
        switch self {
        case .color(let c): return .color(c.withAlpha(opacity))
        case let .linearGradient(s, a, b, sp): return .linearGradient(stops: m(s), start: a, end: b, spread: sp)
        case let .radialGradient(s, c, r0, r1, sp): return .radialGradient(stops: m(s), center: c, startRadius: r0, endRadius: r1, spread: sp)
        case let .conicGradient(s, c, a0, a1): return .conicGradient(stops: m(s), center: c, startAngle: a0, endAngle: a1)
        }
    }
}

public enum RenderFillRule: Hashable, Sendable {
    case nonZero, evenOdd
}

public enum RenderLineCap: Hashable, Sendable {
    case butt, round, square
}

public enum RenderLineJoin: Hashable, Sendable {
    case miter, round, bevel
}

public struct RenderStroke: Equatable, Sendable {
    public var lineWidth: Double
    public var lineCap: RenderLineCap
    public var lineJoin: RenderLineJoin
    public var miterLimit: Double
    public var dash: [Double]
    public var dashPhase: Double
    public init(lineWidth: Double = 1, lineCap: RenderLineCap = .butt, lineJoin: RenderLineJoin = .miter,
                miterLimit: Double = 10, dash: [Double] = [], dashPhase: Double = 0) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dash = dash
        self.dashPhase = dashPhase
    }
}

public enum RenderBlendMode: Hashable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn
    case softLight, hardLight, difference, exclusion, hue, saturation, color, luminosity
    case plusLighter
}

public enum RenderInterpolation: Hashable, Sendable {
    case none, low, medium, high
}

public struct RenderClip: Equatable, Sendable {
    public var path: RenderPath
    public var fillRule: RenderFillRule
    public var inverse: Bool
    public var stroke: RenderStroke?
    public init(path: RenderPath, fillRule: RenderFillRule = .nonZero, inverse: Bool = false, stroke: RenderStroke? = nil) {
        self.path = path
        self.fillRule = fillRule
        self.inverse = inverse
        self.stroke = stroke
    }
}

public enum RenderEffect: Equatable, Sendable {
    case blur(radius: Double)
    case shadow(color: RenderColor, radius: Double, x: Double, y: Double)
    case colorMultiply(RenderColor)
}

public struct RenderGlyphRun: Equatable, Sendable {
    public var source: GlyphSourceRef
    public var size: Double
    public var glyphs: [UInt32]
    public var positions: [CGPoint]
    public var paint: RenderPaint
    public var shear: Double
    public init(source: GlyphSourceRef, size: Double, glyphs: [UInt32], positions: [CGPoint], paint: RenderPaint, shear: Double = 0) {
        self.source = source
        self.size = size
        self.glyphs = glyphs
        self.positions = positions
        self.paint = paint
        self.shear = shear
    }
}

public protocol GlyphOutlineSource: AnyObject, Sendable {
    var unitsPerEm: Double { get }
    func outline(of glyph: UInt32) -> RenderPath?
}

public struct GlyphSourceRef: Hashable, Sendable {
    public let source: any GlyphOutlineSource
    public init(_ source: any GlyphOutlineSource) { self.source = source }
    public static func == (l: GlyphSourceRef, r: GlyphSourceRef) -> Bool { l.source === r.source }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(source)) }
}

public struct DisplayItem: Equatable, Sendable {
    public var id: DisplayItemID
    public var content: Content

    public init(id: DisplayItemID, _ content: Content) {
        self.id = id
        self.content = content
    }

    public enum Content: Equatable, Sendable {
        case fill(RenderPath, RenderPaint, RenderFillRule)
        case stroke(RenderPath, RenderPaint, RenderStroke)
        case glyphs(RenderGlyphRun)
        case image(RenderImage, rect: CGRect, interpolation: RenderInterpolation, opacity: Double)
        case group(DisplayGroup)
        case placeholder(rect: CGRect, tag: String)
    }
}

public struct DisplayGroup: Equatable, Sendable {
    public var transform: RenderTransform
    public var opacity: Double
    public var blendMode: RenderBlendMode
    public var clips: [RenderClip]
    public var mask: DisplayList?
    public var effects: [RenderEffect]
    public var isLayer: Bool
    public var children: [DisplayItem]

    public init(transform: RenderTransform = .identity, opacity: Double = 1, blendMode: RenderBlendMode = .normal,
                clips: [RenderClip] = [], mask: DisplayList? = nil, effects: [RenderEffect] = [],
                isLayer: Bool = false, children: [DisplayItem] = []) {
        self.transform = transform
        self.opacity = opacity
        self.blendMode = blendMode
        self.clips = clips
        self.mask = mask
        self.effects = effects
        self.isLayer = isLayer
        self.children = children
    }

    public var isPlain: Bool {
        transform.isIdentity && opacity == 1 && blendMode == .normal && clips.isEmpty && mask == nil && effects.isEmpty && !isLayer
    }
}

public struct DisplayList: Equatable, Sendable {
    public var items: [DisplayItem]
    public init(_ items: [DisplayItem] = []) { self.items = items }
    public var isEmpty: Bool { items.isEmpty }
}

extension RenderPaint {
    public func translated(_ dx: Double, _ dy: Double) -> RenderPaint {
        func t(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
        switch self {
        case .color: return self
        case let .linearGradient(s, a, b, sp): return .linearGradient(stops: s, start: t(a), end: t(b), spread: sp)
        case let .radialGradient(s, c, r0, r1, sp): return .radialGradient(stops: s, center: t(c), startRadius: r0, endRadius: r1, spread: sp)
        case let .conicGradient(s, c, a0, a1): return .conicGradient(stops: s, center: t(c), startAngle: a0, endAngle: a1)
        }
    }
}

extension DisplayItem {
    public func translated(_ dx: Double, _ dy: Double) -> DisplayItem {
        if dx == 0 && dy == 0 { return self }
        let tr = RenderTransform.translation(dx, dy)
        var out = self
        switch content {
        case let .fill(path, paint, rule):
            out.content = .fill(path.applying(tr), paint.translated(dx, dy), rule)
        case let .stroke(path, paint, stroke):
            out.content = .stroke(path.applying(tr), paint.translated(dx, dy), stroke)
        case .glyphs(var run):
            run.positions = run.positions.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            run.paint = run.paint.translated(dx, dy)
            out.content = .glyphs(run)
        case let .image(img, rect, interpolation, opacity):
            out.content = .image(img, rect: rect.offsetBy(dx: dx, dy: dy), interpolation: interpolation, opacity: opacity)
        case .group(var g):
            g.transform = tr.concatenating(g.transform)
            out.content = .group(g)
        case let .placeholder(rect, tag):
            out.content = .placeholder(rect: rect.offsetBy(dx: dx, dy: dy), tag: tag)
        }
        return out
    }
}

extension RenderColor {
    public func multiplied(by m: RenderColor) -> RenderColor {
        RenderColor(red: red * m.red, green: green * m.green, blue: blue * m.blue, alpha: alpha * m.alpha)
    }
}

extension RenderPaint {
    public func multiplied(by m: RenderColor) -> RenderPaint {
        func ms(_ s: [RenderGradientStop]) -> [RenderGradientStop] { s.map { RenderGradientStop(color: $0.color.multiplied(by: m), location: $0.location) } }
        switch self {
        case .color(let c): return .color(c.multiplied(by: m))
        case let .linearGradient(s, a, b, sp): return .linearGradient(stops: ms(s), start: a, end: b, spread: sp)
        case let .radialGradient(s, c, r0, r1, sp): return .radialGradient(stops: ms(s), center: c, startRadius: r0, endRadius: r1, spread: sp)
        case let .conicGradient(s, c, a0, a1): return .conicGradient(stops: ms(s), center: c, startAngle: a0, endAngle: a1)
        }
    }
}

extension DisplayItem {
    public func multiplyingColors(by m: RenderColor) -> DisplayItem {
        var out = self
        switch content {
        case let .fill(p, paint, r): out.content = .fill(p, paint.multiplied(by: m), r)
        case let .stroke(p, paint, s): out.content = .stroke(p, paint.multiplied(by: m), s)
        case .glyphs(var run):
            run.paint = run.paint.multiplied(by: m)
            out.content = .glyphs(run)
        case .group(var g):
            g.children = g.children.map { $0.multiplyingColors(by: m) }
            out.content = .group(g)
        case .image, .placeholder: break
        }
        return out
    }
}
