public struct ParagraphStyle: Sendable {
    public enum Truncation: Hashable, Sendable { case head, middle, tail }

    public var maxLines: Int?
    public var truncation: Truncation
    public var lineSpacing: Double
    public var minimumScaleFactor: Double
    public var allowsTightening: Bool
    public var baseDirection: TextDirection?
    public var fallbackDirection: TextDirection
    public var ellipsis: Character

    public init(maxLines: Int? = nil, truncation: Truncation = .tail, lineSpacing: Double = 0,
                minimumScaleFactor: Double = 1, allowsTightening: Bool = false,
                baseDirection: TextDirection? = nil, fallbackDirection: TextDirection = .leftToRight,
                ellipsis: Character = "\u{2026}") {
        self.maxLines = maxLines
        self.truncation = truncation
        self.lineSpacing = lineSpacing
        self.minimumScaleFactor = minimumScaleFactor
        self.allowsTightening = allowsTightening
        self.baseDirection = baseDirection
        self.fallbackDirection = fallbackDirection
        self.ellipsis = ellipsis
    }
}

public struct TextLayout: Sendable {
    public struct Line: Sendable {
        public var range: Range<Int>
        public var width: Double
        public var ascent: Double
        public var descent: Double
        public var leading: Double
        public var top: Double
        public var baseline: Double
        public enum Ellipsis: Hashable, Sendable { case none, before, after, inMiddle(at: Int) }
        public var ellipsis: Ellipsis
        public var ellipsisWidth: Double
        public var brokeInsideWord: Bool
        public var direction: TextDirection
        public var visualOrder: [Int]
    }

    public var clusters: [ShapedCluster]
    public var lines: [Line]
    public var width: Double
    public var height: Double
    public var isTruncated: Bool
    public var brokeInsideWord: Bool
    public var breaksUseEstimates: Bool
    public var widthUsesEstimates: Bool
    public var usesEstimates: Bool { breaksUseEstimates || widthUsesEstimates }
    public var scale: Double
    public var naturalLineCount: Int

    public var firstBaseline: Double { lines.first?.baseline ?? 0 }
    public var lastBaseline: Double { lines.last?.baseline ?? 0 }
}

public enum Typesetter {
    static let epsilon = 1e-6

    public static func layout(_ runs: [AttributedRun], width: Double?, maxHeight: Double? = nil,
                              style: ParagraphStyle = ParagraphStyle(),
                              rounding: (Double) -> Double = { $0 }) -> TextLayout {
        var result = layoutOnce(runs, width: width, maxHeight: maxHeight, style: style, scale: 1, tightening: 0,
                                rounding: rounding)
        guard result.isTruncated, width != nil else { return result }
        if style.allowsTightening {
            let tight = layoutOnce(runs, width: width, maxHeight: maxHeight, style: style, scale: 1,
                                   tightening: 0.03, rounding: rounding)
            if !tight.isTruncated { return tight }
        }
        let minScale = max(min(style.minimumScaleFactor, 1), 0.01)
        guard minScale < 1 else { return result }
        let smallest = layoutOnce(runs, width: width, maxHeight: maxHeight, style: style, scale: minScale,
                                  tightening: 0, rounding: rounding)
        guard !smallest.isTruncated else { return smallest }
        var lo = minScale, hi = 1.0
        result = smallest
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            let r = layoutOnce(runs, width: width, maxHeight: maxHeight, style: style, scale: mid, tightening: 0,
                               rounding: rounding)
            if r.isTruncated { hi = mid } else { lo = mid; result = r }
        }
        return result
    }

    static func layoutOnce(_ runs0: [AttributedRun], width: Double?, maxHeight: Double?, style: ParagraphStyle,
                           scale: Double, tightening: Double, rounding: (Double) -> Double) -> TextLayout {
        let runs = runs0.map { r -> AttributedRun in
            var s = r.style.scaled(scale)
            s.tracking -= tightening * s.size
            return AttributedRun(r.text, style: s)
        }
        let c = Measure(runs: runs)
        let n = c.clusters.count
        let opportunities = LineBreaker.opportunities(classes: c.clusters.map(\.breakClass))
        var breakEstimates = false
        var widthEstimates = false
        let limitWidth = width.map { max($0, 0) }

        var paragraphs: [Range<Int>] = []
        var ps = 0
        for i in 1...max(n, 1) where i <= n && (opportunities[i] == .mandatory) {
            if i == n {
                paragraphs.append(ps..<n)
            } else {
                paragraphs.append(ps..<i)
                ps = i
            }
        }
        if paragraphs.isEmpty { paragraphs = [0..<0] }

        struct Raw { var range: Range<Int>; var paragraph: Int; var inside: Bool }
        var raw: [Raw] = []
        for (pi, p) in paragraphs.enumerated() {
            let full = c.width(p, strip: .trailing)
            if full.estimated && limitWidth != nil && limitWidth! > 0 { breakEstimates = true }
            guard let w = limitWidth, full.width > w + epsilon, !p.isEmpty else {
                raw.append(Raw(range: p, paragraph: pi, inside: false))
                continue
            }
            if w > 0 && p.count > 1 && c.anyEstimates(p) { breakEstimates = true }
            var start = p.lowerBound
            while start < p.upperBound {
                var lastBreak: Int?
                var end = p.upperBound
                var inside = false
                var x = 0.0
                var visible = 0.0
                var i = start
                while i < p.upperBound {
                    let cl = c.clusters[i]
                    let isBreak = cl.breakClass == .BK || cl.breakClass == .CR || cl.breakClass == .LF || cl.breakClass == .NL
                    if !cl.hangs && !isBreak {
                        visible = x + cl.advance
                        if visible > w + epsilon && i > start {
                            if let b = lastBreak, b > start { end = b } else { end = i; inside = true }
                            break
                        }
                    }
                    x += cl.advance + cl.kernAfter
                    if i + 1 < p.upperBound && opportunities[i + 1] == .allowed { lastBreak = i + 1 }
                    i += 1
                }
                if end - start == 1 && c.width(start..<end, strip: .trailing).width > w + epsilon
                    && end < p.upperBound && opportunities[end] != .allowed {
                    inside = true
                }
                raw.append(Raw(range: start..<end, paragraph: pi, inside: inside))
                start = end
            }
        }
        let naturalCount = raw.count

        var cap = style.maxLines.map { max($0, 1) } ?? Int.max
        if let h = maxHeight, h.isFinite {
            var k = 1
            while k < raw.count {
                let candidate = c.stackHeight(raw.prefix(k + 1).map(\.range), lineSpacing: style.lineSpacing)
                if rounding(candidate) > h + epsilon { break }
                k += 1
            }
            cap = min(cap, k)
        }

        var lines: [TextLayout.Line] = []
        var truncated = false
        let shown = min(cap, raw.count)
        for li in 0..<shown {
            let r = raw[li]
            var range = r.range
            var ellipsis = TextLayout.Line.Ellipsis.none
            var ellipsisWidth = 0.0
            var lineWidth: Double
            if li == shown - 1 && raw.count > shown {
                truncated = true
                let p = paragraphs[r.paragraph]
                var contentEnd = p.upperBound
                while contentEnd > range.lowerBound, c.isBreak(contentEnd - 1) { contentEnd -= 1 }
                let t = c.truncate(range.lowerBound..<contentEnd, width: limitWidth, mode: style.truncation,
                                   ellipsis: style.ellipsis)
                if limitWidth != 0 && c.anyEstimates(range.lowerBound..<contentEnd) { breakEstimates = true }
                range = t.range
                ellipsis = t.ellipsis
                ellipsisWidth = t.ellipsisWidth
                lineWidth = t.width
            } else {
                let m = c.width(range, strip: .trailing)
                if m.estimated && limitWidth != 0 { widthEstimates = true }
                lineWidth = m.width
            }
            lines.append(TextLayout.Line(range: range, width: lineWidth, ascent: 0, descent: 0, leading: 0,
                                         top: 0, baseline: 0, ellipsis: ellipsis, ellipsisWidth: ellipsisWidth,
                                         brokeInsideWord: r.inside, direction: .leftToRight, visualOrder: []))
        }

        if lines.count == 1, paragraphs.count == 1, let w = limitWidth, w > 0, let p = paragraphs.first, !p.isEmpty,
           !(p.lowerBound + 1..<p.upperBound).contains(where: { opportunities[$0] == .allowed }) {
            let full = c.width(p, strip: .trailing)
            if !full.estimated && full.width > w + epsilon {
                breakEstimates = false
                lines[0].brokeInsideWord = true
            }
        }

        var y = 0.0
        for k in lines.indices {
            let m = c.metrics(raw[k].range)
            lines[k].ascent = m.ascent
            lines[k].descent = m.descent
            lines[k].leading = m.leading
            if k > 0 {
                let p = lines[k - 1]
                y += p.ascent + p.descent + p.leading + style.lineSpacing
            }
            lines[k].top = y
            lines[k].baseline = y + m.ascent
        }
        let height = lines.last.map { $0.top + $0.ascent + $0.descent } ?? 0

        var bidiByParagraph: [Int: BidiParagraph] = [:]
        for k in lines.indices {
            let pi = raw[k].paragraph
            let p = paragraphs[pi]
            let bidi = bidiByParagraph[pi] ?? BidiParagraph(c.clusters[p].map(\.character), base: style.baseDirection,
                                                           fallback: style.fallbackDirection)
            bidiByParagraph[pi] = bidi
            lines[k].direction = bidi.direction
            let local = (lines[k].range.lowerBound - p.lowerBound)..<(lines[k].range.upperBound - p.lowerBound)
            lines[k].visualOrder = bidi.visualOrder(local).map { $0 + p.lowerBound }
        }

        return TextLayout(clusters: c.clusters, lines: lines, width: lines.map(\.width).max() ?? 0, height: height,
                          isTruncated: truncated, brokeInsideWord: lines.contains { $0.brokeInsideWord },
                          breaksUseEstimates: breakEstimates, widthUsesEstimates: widthEstimates, scale: scale, naturalLineCount: naturalCount)
    }
}

struct Measure {
    let runs: [AttributedRun]
    let clusters: [ShapedCluster]

    init(runs: [AttributedRun]) {
        self.runs = runs
        clusters = Shaper.shape(runs)
    }

    enum Strip { case none, trailing, leading, both }

    func isBreak(_ i: Int) -> Bool {
        let b = clusters[i].breakClass
        return b == .BK || b == .CR || b == .LF || b == .NL
    }

    func anyEstimates(_ r: Range<Int>) -> Bool {
        r.contains { runs[clusters[$0].run].style.face.advancesAreEstimates }
    }

    func width(_ range: Range<Int>, strip: Strip) -> (width: Double, estimated: Bool) {
        var lo = range.lowerBound, hi = range.upperBound
        if strip == .trailing || strip == .both {
            while hi > lo && (clusters[hi - 1].hangs || isBreak(hi - 1)) { hi -= 1 }
        }
        if strip == .leading || strip == .both {
            while lo < hi && clusters[lo].hangs { lo += 1 }
        }
        guard lo < hi else { return (0, false) }
        var w = 0.0
        var estimated = false
        var s = lo
        while s < hi {
            let run = clusters[s].run
            var e = s
            while e < hi && clusters[e].run == run { e += 1 }
            let st = runs[run].style
            let text = String(clusters[s..<e].map(\.character))
            if let m = st.face.measuredWidth(of: text[...], size: st.size) {
                w += m + Double(e - s) * st.tracking
            } else {
                for k in s..<e { w += clusters[k].advance + (k < hi - 1 ? clusters[k].kernAfter : 0) }
                if st.face.advancesAreEstimates { estimated = true }
            }
            s = e
        }
        return (w, estimated)
    }

    func advanceWidth(_ lo: Int, _ hi: Int) -> Double {
        guard lo < hi else { return 0 }
        var w = 0.0
        for k in lo..<hi { w += clusters[k].advance + (k < hi - 1 ? clusters[k].kernAfter : 0) }
        return w
    }

    func ellipsisWidth(_ ch: Character, run: Int) -> Double {
        guard runs.indices.contains(run) else { return 0 }
        let shaped = Shaper.shape([AttributedRun(String(ch), style: runs[run].style)])
        return shaped.first?.advance ?? 0
    }

    struct Truncated {
        var range: Range<Int>
        var ellipsis: TextLayout.Line.Ellipsis
        var ellipsisWidth: Double
        var width: Double
    }

    func truncate(_ r: Range<Int>, width: Double?, mode: ParagraphStyle.Truncation, ellipsis ch: Character) -> Truncated {
        let runIndex = r.isEmpty ? 0 : clusters[mode == .head ? r.upperBound - 1 : r.lowerBound].run
        let e = ellipsisWidth(ch, run: runIndex)
        func stripT(_ lo: Int, _ hi: Int) -> Int {
            var h = hi
            while h > lo && clusters[h - 1].hangs { h -= 1 }
            return h
        }
        func stripL(_ lo: Int, _ hi: Int) -> Int {
            var l = lo
            while l < hi && clusters[l].hangs { l += 1 }
            return l
        }
        guard let w = width else {
            let hi = stripT(r.lowerBound, r.upperBound)
            return Truncated(range: r.lowerBound..<hi, ellipsis: .after, ellipsisWidth: e,
                             width: advanceWidth(r.lowerBound, hi) + e)
        }
        switch mode {
        case .tail:
            var k = r.upperBound
            while k > r.lowerBound {
                let hi = stripT(r.lowerBound, k)
                if advanceWidth(r.lowerBound, hi) + e <= w + Typesetter.epsilon {
                    return Truncated(range: r.lowerBound..<hi, ellipsis: .after, ellipsisWidth: e,
                                     width: advanceWidth(r.lowerBound, hi) + e)
                }
                k -= 1
            }
            return Truncated(range: r.lowerBound..<r.lowerBound, ellipsis: .after, ellipsisWidth: e, width: e)
        case .head:
            var k = r.lowerBound
            while k < r.upperBound {
                let lo = stripL(k, r.upperBound)
                if e + advanceWidth(lo, r.upperBound) <= w + Typesetter.epsilon {
                    return Truncated(range: lo..<r.upperBound, ellipsis: .before, ellipsisWidth: e,
                                     width: e + advanceWidth(lo, r.upperBound))
                }
                k += 1
            }
            return Truncated(range: r.upperBound..<r.upperBound, ellipsis: .before, ellipsisWidth: e, width: e)
        case .middle:
            let count = r.count
            var m = count
            while m >= 0 {
                let p = (m + 1) / 2, q = m - p
                let headEnd = stripT(r.lowerBound, r.lowerBound + p)
                let tailStart = stripL(r.upperBound - q, r.upperBound)
                let total = advanceWidth(r.lowerBound, headEnd) + e + advanceWidth(tailStart, r.upperBound)
                if total <= w + Typesetter.epsilon || m == 0 {
                    return Truncated(range: r.lowerBound..<r.upperBound, ellipsis: .inMiddle(at: headEnd),
                                     ellipsisWidth: e, width: total)
                }
                m -= 1
            }
            return Truncated(range: r, ellipsis: .inMiddle(at: r.lowerBound), ellipsisWidth: e, width: e)
        }
    }

    func metrics(_ r: Range<Int>) -> LineMetrics {
        var best: LineMetrics?
        func merge(_ m: LineMetrics, offset: Double) {
            let a = m.ascent + max(offset, 0), d = m.descent + max(-offset, 0)
            if var b = best {
                b.ascent = max(b.ascent, a)
                b.descent = max(b.descent, d)
                b.leading = max(b.leading, m.leading)
                best = b
            } else {
                best = LineMetrics(ascent: a, descent: d, leading: m.leading, capHeight: m.capHeight, xHeight: m.xHeight)
            }
        }
        var seen = Set<String>()
        for k in r {
            let cl = clusters[k]
            let st = runs[cl.run].style
            let key = "\(ObjectIdentifier(cl.face).hashValue)/\(st.size)/\(st.baselineOffset)"
            if seen.insert(key).inserted { merge(cl.face.lineMetrics(size: st.size), offset: st.baselineOffset) }
        }
        if let b = best { return b }
        let runIndex = r.lowerBound < clusters.count ? clusters[r.lowerBound].run
            : (clusters.last?.run ?? 0)
        guard runs.indices.contains(runIndex) else { return LineMetrics(ascent: 0, descent: 0, leading: 0) }
        let st = runs[runIndex].style
        merge(st.face.lineMetrics(size: st.size), offset: st.baselineOffset)
        return best!
    }

    func stackHeight(_ ranges: [Range<Int>], lineSpacing: Double) -> Double {
        var y = 0.0
        var last: LineMetrics?
        for r in ranges {
            let m = metrics(r)
            if let p = last { y += p.ascent + p.descent + p.leading + lineSpacing }
            last = m
        }
        return last.map { y + $0.ascent + $0.descent } ?? 0
    }
}
