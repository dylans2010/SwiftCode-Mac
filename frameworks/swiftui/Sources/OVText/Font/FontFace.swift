public typealias GlyphID = UInt32

public struct FontTraits: Hashable, Sendable {
    public var weight: Int
    public var width: Int
    public var isItalic: Bool
    public var isMonospaced: Bool

    public init(weight: Int = 400, width: Int = 5, isItalic: Bool = false, isMonospaced: Bool = false) {
        self.weight = weight
        self.width = width
        self.isItalic = isItalic
        self.isMonospaced = isMonospaced
    }
}

public struct LineMetrics: Hashable, Sendable {
    public var ascent: Double
    public var descent: Double
    public var leading: Double
    public var capHeight: Double
    public var xHeight: Double

    public init(ascent: Double, descent: Double, leading: Double, capHeight: Double = 0, xHeight: Double = 0) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
        self.capHeight = capHeight
        self.xHeight = xHeight
    }

    public var lineHeight: Double { ascent + descent }

    public func scaled(by s: Double) -> LineMetrics {
        LineMetrics(ascent: ascent * s, descent: descent * s, leading: leading * s,
                    capHeight: capHeight * s, xHeight: xHeight * s)
    }
}

public protocol FontFace: AnyObject, Sendable {
    var familyName: String { get }
    var styleName: String { get }
    var traits: FontTraits { get }

    func lineMetrics(size: Double) -> LineMetrics
    func glyph(for scalar: Unicode.Scalar) -> GlyphID?
    func advance(of glyph: GlyphID, size: Double) -> Double
    func kerning(_ left: GlyphID, _ right: GlyphID, size: Double) -> Double
    func tracking(size: Double) -> Double

    func measuredWidth(of text: Substring, size: Double) -> Double?
    var advancesAreEstimates: Bool { get }
}

extension FontFace {
    public func tracking(size: Double) -> Double { 0 }
    public func measuredWidth(of text: Substring, size: Double) -> Double? { nil }
    public var advancesAreEstimates: Bool { false }
}
