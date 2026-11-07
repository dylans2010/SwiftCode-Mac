import AppKit
import CoreText
import YcodeIDECore

extension Theme {
    static func isCellCharacter(_ u: UInt16) -> Bool {
        (0x2500...0x25FF).contains(u) || (0x2800...0x28FF).contains(u)
    }

    static func fixCellWidths(_ storage: NSTextStorage, in range: NSRange) {
        let text = storage.string as NSString
        let end = min(NSMaxRange(range), text.length)
        var i = max(0, range.location)
        let advance = CGFloat(EditorMetrics.advance(fontAdvance: Double(Theme.advance)))
        var cache: [String: NSFont] = [:]
        while i < end {
            let u = text.character(at: i)
            guard isCellCharacter(u) else { i += 1; continue }
            var j = i + 1
            while j < end, isCellCharacter(text.character(at: j)) { j += 1 }
            let run = NSRange(location: i, length: j - i)
            let base = (storage.attribute(.font, at: i, effectiveRange: nil) as? NSFont) ?? font
            let s = text.substring(with: run)
            if let fixed = cellFont(for: s, base: base, advance: advance, cache: &cache) {
                storage.addAttribute(.font, value: fixed, range: run)
            }
            i = j
        }
    }

    static func cellFont(for s: String, base: NSFont, advance: CGFloat, cache: inout [String: NSFont]) -> NSFont? {
        let ct = base as CTFont
        let chars = Array(s.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        let has = CTFontGetGlyphsForCharacters(ct, chars, &glyphs, chars.count)
        let face: CTFont = has ? ct : CTFontCreateForString(ct, s as CFString, CFRange(location: 0, length: (s as NSString).length))
        let key = "\(CTFontCopyPostScriptName(face)) \(CTFontGetSize(face)) \(advance)"
        if let f = cache[key] { return f === base ? nil : f }
        var g: CGGlyph = 0
        var c = chars[0]
        CTFontGetGlyphsForCharacters(face, &c, &g, 1)
        var adv = CGSize.zero
        CTFontGetAdvancesForGlyphs(face, .horizontal, &g, &adv, 1)
        if has, abs(adv.width - advance) < 0.01 { cache[key] = base; return nil }
        let desc = (face as NSFont).fontDescriptor.addingAttributes([.fixedAdvance: advance])
        let fixed = NSFont(descriptor: desc, size: base.pointSize) ?? (face as NSFont)
        cache[key] = fixed
        return fixed
    }
}
