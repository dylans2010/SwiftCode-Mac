import Foundation
import Synchronization
import OVText

package struct TextFont: Hashable, Sendable {
    package var size: CGFloat
    package var weight: Font.Weight
    package var width: Font.Width
    package var design: Font.Design
    package var isItalic: Bool
    package var family: String?
    package var leading: Font.Leading
    package var isMonospacedDigit: Bool
    package var smallCaps: Font.SmallCaps
    package var textStyle: Font.TextStyle?

    package init(size: CGFloat, weight: Font.Weight = .regular, width: Font.Width = .standard,
                 design: Font.Design = .default, isItalic: Bool = false, family: String? = nil,
                 leading: Font.Leading = .standard, isMonospacedDigit: Bool = false,
                 smallCaps: Font.SmallCaps = [], textStyle: Font.TextStyle? = nil) {
        self.size = size
        self.weight = weight
        self.width = width
        self.design = design
        self.isItalic = isItalic
        self.family = family
        self.leading = leading
        self.isMonospacedDigit = isMonospacedDigit
        self.smallCaps = smallCaps
        self.textStyle = textStyle
    }

    package static func style(_ s: Font.TextStyle, _ size: DynamicTypeSize = .large) -> TextFont {
        Font(base: .style(s)).resolvedTextFont(Font.Context(dynamicTypeSize: size))
    }

    package static let body = TextFont.style(.body)

    package var isBold: Bool { weight.value >= Font.Weight.bold.value }

    package func bolded() -> TextFont { var f = self; f.weight = .bold; return f }
}

package struct ResolvedText: Hashable, Sendable {
    package struct Run: Hashable, Sendable {
        package var string: String
        package var font: TextFont
        package var tracking: CGFloat
        package var kerning: CGFloat
        package var baselineOffset: CGFloat
        package var color: Color.Resolved?

        package init(string: String, font: TextFont, tracking: CGFloat = 0, kerning: CGFloat = 0,
                     baselineOffset: CGFloat = 0, color: Color.Resolved? = nil) {
            self.string = string
            self.font = font
            self.tracking = tracking
            self.kerning = kerning
            self.baselineOffset = baselineOffset
            self.color = color
        }
    }

    package struct Paragraph: Hashable, Sendable {
        package var lineLimit: Int?
        package var minimumLines: Int?
        package var lineSpacing: CGFloat = 0
        package var alignment: TextAlignment = .leading
        package var truncation: Text.TruncationMode = .tail
        package var minimumScaleFactor: CGFloat = 1
        package var allowsTightening = false
        package var layoutDirection: LayoutDirection = .leftToRight
        package var displayScale: CGFloat = 3

        package init(lineLimit: Int? = nil) { self.lineLimit = lineLimit }

        package init(environment e: EnvironmentValues) {
            lineLimit = e.lineLimit
            minimumLines = e.lineLimitMinimum
            lineSpacing = e.lineSpacing
            alignment = e.multilineTextAlignment
            truncation = e.truncationMode
            minimumScaleFactor = e.minimumScaleFactor
            allowsTightening = e.allowsTightening
            layoutDirection = e.layoutDirection
            displayScale = e.displayScale
        }
    }

    package var runs: [Run]
    package var paragraph: Paragraph

    package init(runs: [Run], paragraph: Paragraph) {
        self.runs = runs
        self.paragraph = paragraph
    }

    package init(_ string: String, font: TextFont = .body, lineLimit: Int? = nil) {
        self.init(runs: [Run(string: string, font: font)], paragraph: Paragraph(lineLimit: lineLimit))
    }

    package var string: String { runs.map(\.string).joined() }
    package var firstFont: TextFont { runs.first?.font ?? .body }
    package var lastFont: TextFont { runs.last?.font ?? .body }
}

package struct TextMeasurement: Sendable {
    package var size: CGSize
    package var firstBaseline: CGFloat?
    package var lastBaseline: CGFloat?
    package var unknown: Axis.Set

    package init(size: CGSize, firstBaseline: CGFloat?, lastBaseline: CGFloat?, unknown: Axis.Set = []) {
        self.size = size
        self.firstBaseline = firstBaseline
        self.lastBaseline = lastBaseline
        self.unknown = unknown
    }
}

package struct TextSpacing: Sendable {
    package var above: SpacingPreference
    package var below: SpacingPreference

    package init(above: SpacingPreference, below: SpacingPreference) {
        self.above = above
        self.below = below
    }
}

package protocol TextMeasurer: Sendable {
    func measure(_ text: ResolvedText, proposal: ProposedViewSize) -> TextMeasurement
    func spacing(for font: TextFont) -> TextSpacing
}

package protocol TextFontProvider: Sendable {
    func face(for font: TextFont) -> any FontFace
    var fallbackCatalog: FontCatalog? { get }
    func spacing(for font: TextFont) -> TextSpacing
}

extension TextFontProvider {
    package var fallbackCatalog: FontCatalog? { nil }

    package func spacing(for font: TextFont) -> TextSpacing {
        let size = Double(font.size)
        let m = face(for: font).lineMetrics(size: size)
        return TextSpacing(
            above: SpacingPreference(kind: .text, towardStandard: CGFloat(max(1.33056 * size - m.ascent, 0)), towardText: 2),
            below: SpacingPreference(kind: .text, towardStandard: CGFloat(max(0.86726 * size - m.descent, 0)), towardText: 2))
    }
}

package struct CatalogFontProvider: TextFontProvider {
    package let catalog: FontCatalog

    package init(catalog: FontCatalog = .shared) { self.catalog = catalog }

    package var fallbackCatalog: FontCatalog? { catalog }

    package func face(for font: TextFont) -> any FontFace {
        let design: FontDesignClass
        switch font.design {
        case .default: design = .default
        case .serif: design = .serif
        case .rounded: design = .rounded
        case .monospaced: design = .monospaced
        }
        let traits = FontTraits(weight: font.weight.weightClass, width: font.width.widthClass,
                                isItalic: font.isItalic, isMonospaced: font.design == .monospaced)
        if let f = catalog.face(for: FontRequest(family: font.family, design: design, traits: traits)) { return f }
        return EmptyFace.shared
    }
}

final class EmptyFace: FontFace, @unchecked Sendable {
    static let shared = EmptyFace()
    let familyName = "Empty"
    let styleName = "Regular"
    let traits = FontTraits()
    func lineMetrics(size: Double) -> LineMetrics { LineMetrics(ascent: size * 0.8, descent: size * 0.2, leading: 0) }
    func glyph(for scalar: Unicode.Scalar) -> GlyphID? { nil }
    func advance(of glyph: GlyphID, size: Double) -> Double { size * 0.5 }
    func kerning(_ left: GlyphID, _ right: GlyphID, size: Double) -> Double { 0 }
}

package final class TypesetTextMeasurer: TextMeasurer, @unchecked Sendable {
    package let fonts: any TextFontProvider
    package var emptyLineHeightRatio: CGFloat = 14.0 / 17.0
    package var emptyBaselineRatio: CGFloat = 11.0 / 17.0

    private struct Key: Hashable {
        let text: ResolvedText
        let w: CGFloat?
        let h: CGFloat?
    }
    private let cache = Mutex<[Key: TextMeasurement]>([:])

    package init(fonts: any TextFontProvider) { self.fonts = fonts }

    package static let shared = TypesetTextMeasurer(fonts: CatalogFontProvider())

    package func spacing(for font: TextFont) -> TextSpacing { fonts.spacing(for: font) }

    private static func ceilPx(_ v: Double, _ scale: CGFloat) -> CGFloat {
        let s = Double(scale)
        return CGFloat((v * s - 1e-4).rounded(.up) / s)
    }

    private static func roundPx(_ v: Double, _ scale: CGFloat) -> CGFloat {
        let s = Double(scale)
        return CGFloat((v * s).rounded() / s)
    }

    private static func leadingAdjustment(_ f: TextFont) -> Double {
        switch f.leading {
        case .standard: return 0
        case .tight: return -0.07 * Double(f.size)
        case .loose: return 0.07 * Double(f.size)
        }
    }

    package func layout(_ text: ResolvedText, width: CGFloat?, height: CGFloat?) -> TextLayout {
        let runs = text.runs.map { r in
            AttributedRun(r.string, style: RunStyle(face: fonts.face(for: r.font), size: Double(r.font.size),
                                                    tracking: Double(r.tracking), kerning: Double(r.kerning),
                                                    baselineOffset: Double(r.baselineOffset),
                                                    fallback: fonts.fallbackCatalog))
        }
        let p = text.paragraph
        let truncation: ParagraphStyle.Truncation
        switch p.truncation {
        case .head: truncation = .head
        case .middle: truncation = .middle
        case .tail: truncation = .tail
        }
        let style = ParagraphStyle(
            maxLines: p.lineLimit, truncation: truncation,
            lineSpacing: Double(p.lineSpacing) + TypesetTextMeasurer.leadingAdjustment(text.firstFont),
            minimumScaleFactor: Double(p.minimumScaleFactor), allowsTightening: p.allowsTightening,
            fallbackDirection: p.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight)
        let scale = p.displayScale
        return Typesetter.layout(runs, width: width.map(Double.init), maxHeight: height.map(Double.init),
                                 style: style, rounding: { Double(TypesetTextMeasurer.ceilPx($0, scale)) })
    }

    package struct PlacedLine: Sendable {
        package var line: TextLayout.Line
        package var origin: CGPoint
    }

    package func placedLines(_ text: ResolvedText, size: CGSize) -> [PlacedLine] {
        placedLayout(text, size: size).lines
    }

    package func placedLayout(_ text: ResolvedText, size: CGSize) -> (layout: TextLayout, lines: [PlacedLine]) {
        let l = layout(text, width: size.width, height: size.height)
        let scale = text.paragraph.displayScale
        let rtl = text.paragraph.layoutDirection == .rightToLeft
        let lines = l.lines.map { line in
            let slack = Double(size.width) - line.width
            let x: Double
            switch text.paragraph.alignment {
            case .leading: x = rtl ? slack : 0
            case .center: x = slack / 2
            case .trailing: x = rtl ? 0 : slack
            }
            return PlacedLine(line: line, origin: CGPoint(x: CGFloat(x),
                                                          y: TypesetTextMeasurer.roundPx(line.baseline, scale)))
        }
        return (l, lines)
    }

    package func measure(_ text: ResolvedText, proposal p: ProposedViewSize) -> TextMeasurement {
        let key = Key(text: text, w: p.width, h: p.height)
        if let m = cache.withLock({ $0[key] }) { return m }
        let m = compute(text, p)
        cache.withLock {
            if $0.count > 8192 { $0.removeAll(keepingCapacity: true) }
            $0[key] = m
        }
        return m
    }

    private func compute(_ text: ResolvedText, _ p: ProposedViewSize) -> TextMeasurement {
        let scale = text.paragraph.displayScale
        let width = p.width.flatMap { $0.isFinite ? max($0, 0) : nil }
        let height = p.height.flatMap { $0.isFinite ? max($0, 0) : nil }
        if text.string.isEmpty {
            if p.width == 0 && p.height == 0 {
                return TextMeasurement(size: .zero, firstBaseline: 0, lastBaseline: 0)
            }
            let size = text.firstFont.size
            let b = TypesetTextMeasurer.roundPx(Double(emptyBaselineRatio * size), scale)
            return TextMeasurement(size: CGSize(width: 0, height: TypesetTextMeasurer.ceilPx(Double(emptyLineHeightRatio * size), scale)),
                                   firstBaseline: b, lastBaseline: b)
        }
        if p.width == 0 && p.height == 0 {
            let l = layout(text, width: nil, height: nil)
            let b = TypesetTextMeasurer.roundPx(l.firstBaseline, scale)
            return TextMeasurement(size: .zero, firstBaseline: b, lastBaseline: b)
        }
        let l = layout(text, width: width, height: height)
        var w = TypesetTextMeasurer.ceilPx(l.width, scale)
        if let pw = width {
            if l.brokeInsideWord { w = pw }
            w = min(w, pw)
        }
        var h = l.height
        if let minLines = text.paragraph.minimumLines, l.lines.count < minLines, let last = l.lines.last {
            let pitch = last.ascent + last.descent + last.leading + Double(text.paragraph.lineSpacing)
            h += Double(minLines - l.lines.count) * pitch
        }
        var unknown: Axis.Set = []
        if l.breaksUseEstimates {
            unknown = [.horizontal, .vertical]
        } else if l.widthUsesEstimates && !(l.brokeInsideWord && width != nil) {
            unknown = [.horizontal]
        }
        return TextMeasurement(size: CGSize(width: w, height: TypesetTextMeasurer.ceilPx(h, scale)),
                               firstBaseline: TypesetTextMeasurer.roundPx(l.firstBaseline, scale),
                               lastBaseline: TypesetTextMeasurer.roundPx(l.lastBaseline, scale),
                               unknown: unknown)
    }
}
