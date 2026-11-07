import Foundation
import SwiftSyntax

public final class SyntaxDocument {
    public let language: SyntaxLanguage
    public let usesParser: Bool
    public private(set) var units: [UInt16]
    private var lineStarts: [Int] = [0]
    private var lineTokens: [[SyntaxToken]] = [[]]
    private var lexStates: [LexState] = [.initial]
    private let lexer: (any LineLexer)?
    private let classifier: SwiftClassifier?
    private var utf8: [UInt8] = []
    private var lineStarts8: [Int] = [0]
    private var ascii = true
    private var parsed = false
    private var pendingEdits: [SourceEdit] = []
    private var parserDirty: Range<Int>?
    var eventCache: [[BlockEvent]?] = [nil]

    public struct UpdateStats: Equatable, Sendable {
        public var linesLexed: Int
        public var full: Bool
    }
    public private(set) var lastUpdate = UpdateStats(linesLexed: 0, full: true)
    public private(set) var lastRefineDuration: Double = 0

    public init(text: String, language: SyntaxLanguage, usesParser: Bool = true, deferParse: Bool = false) {
        self.language = language
        self.usesParser = usesParser && language == .swift
        units = Array(text.utf16)
        lexer = SyntaxLexers.lexer(for: language)
        classifier = self.usesParser ? SwiftClassifier() : nil
        reload()
        if !deferParse { refine() }
    }

    public var text: String { String(decoding: units, as: UTF16.self) }

    public func setText(_ text: String) {
        units = Array(text.utf16)
        reload()
    }

    private func reload() {
        lineStarts = [0]
        for (i, u) in units.enumerated() where u == 10 { lineStarts.append(i + 1) }
        lineTokens = Array(repeating: [], count: lineStarts.count)
        lexStates = Array(repeating: .initial, count: lineStarts.count)
        eventCache = Array(repeating: nil, count: lineStarts.count)
        var state = LexState.initial
        lexLines(0..<lineCount, state: &state)
        if classifier != nil {
            utf8 = Array(String(decoding: units, as: UTF16.self).utf8)
            ascii = utf8.count == units.count
            lineStarts8 = ascii ? lineStarts : utf8Starts(lineStarts)
            parsed = false
            pendingEdits = []
            parserDirty = 0..<units.count
        }
        lastUpdate = UpdateStats(linesLexed: lineCount, full: true)
    }

    public var hasParsed: Bool { parsed }

    public var needsRefinement: Bool { classifier != nil && parserDirty != nil }

    @discardableResult
    public func refine() -> Range<Int>? {
        guard let classifier, let dirty = parserDirty else { return nil }
        let t0 = Date()
        defer { lastRefineDuration = Date().timeIntervalSince(t0); parserDirty = nil; pendingEdits = [] }
        if !parsed {
            classifier.parse(utf8)
            parsed = true
            classifyLines(0..<lineCount)
            lastUpdate = UpdateStats(linesLexed: lineCount, full: true)
            return 0..<units.count
        }
        classifier.reparse(utf8, edits: pendingEdits)
        var lA = line(containing: dirty.lowerBound)
        while lA > 0, lexStates[lA - 1].open != nil { lA -= 1 }
        var last = line(containing: max(dirty.lowerBound, dirty.upperBound - 1)) + 1
        classifyLines(lA..<last)
        var chunk = 4
        var equalRun = 0
        scan: while last < lineCount {
            let b = min(lineCount, last + chunk)
            let old = Array(lineTokens[last..<b])
            classifyLines(last..<b)
            for k in last..<b {
                equalRun = lineTokens[k] == old[k - last] ? equalRun + 1 : 0
                if equalRun == 2 { last = k + 1; break scan }
            }
            last = b
            chunk *= 2
        }
        lastUpdate = UpdateStats(linesLexed: last - lA, full: false)
        return lineStarts[lA]..<(last < lineCount ? lineStarts[last] : units.count)
    }

    public var lineCount: Int { lineStarts.count }

    public func line(containing offset: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    public func lineStart(_ n: Int) -> Int { lineStarts[n] }

    public func lineRange(_ n: Int) -> Range<Int> {
        let s = lineStarts[n]
        var e = n + 1 < lineStarts.count ? lineStarts[n + 1] - 1 : units.count
        if e > s, units[e - 1] == 13 { e -= 1 }
        return s..<e
    }

    public func lineText(_ n: Int) -> String {
        String(decoding: units[lineRange(n)], as: UTF16.self)
    }

    public func leadingWhitespace(_ n: Int) -> String {
        let r = lineRange(n)
        var e = r.lowerBound
        while e < r.upperBound, units[e] == 32 || units[e] == 9 { e += 1 }
        return String(decoding: units[r.lowerBound..<e], as: UTF16.self)
    }

    public func startState(ofLine n: Int) -> LexState { n == 0 ? .initial : lexStates[n - 1] }

    public func tokens(onLine n: Int) -> [SyntaxToken] {
        let s = lineStarts[n]
        return lineTokens[n].map { SyntaxToken(kind: $0.kind, location: $0.location + s, length: $0.length) }
    }

    public func tokens(in range: Range<Int>) -> [SyntaxToken] {
        let a = line(containing: range.lowerBound), b = line(containing: max(range.lowerBound, range.upperBound))
        var out: [SyntaxToken] = []
        for n in a...b {
            let s = lineStarts[n]
            for t in lineTokens[n] where t.location + s < range.upperBound && t.location + s + t.length > range.lowerBound {
                out.append(SyntaxToken(kind: t.kind, location: t.location + s, length: t.length))
            }
        }
        return out
    }

    public func token(at offset: Int) -> SyntaxToken? {
        let n = line(containing: offset)
        let s = lineStarts[n]
        for t in lineTokens[n] where t.location + s <= offset && offset < t.location + s + t.length {
            return SyntaxToken(kind: t.kind, location: t.location + s, length: t.length)
        }
        return nil
    }

    public func isInsideCommentOrString(_ offset: Int) -> Bool {
        let n = line(containing: offset)
        let s = lineStarts[n]
        for t in lineTokens[n] where t.kind.isCommentOrString {
            let a = t.location + s, b = a + t.length
            if offset > a && offset < b { return true }
            if offset == b, offset > a, !isClosed(a, b, kind: t.kind) { return true }
        }
        return false
    }

    private func isClosed(_ a: Int, _ b: Int, kind: SyntaxTokenKind) -> Bool {
        let last = units[b - 1]
        switch kind {
        case .comment, .docComment:
            return b - a >= 4 && ((last == 47 && units[b - 2] == 42) || (last == 62 && units[b - 2] == 45))
        case .codeSpan:
            return b - a >= 2 && last == 96
        default:
            guard b - a >= 2, last == 34 || last == 39 || last == 96 || last == 35 || last == 47 else { return false }
            var k = b - 2, slashes = 0
            while k >= a, units[k] == 92 { slashes += 1; k -= 1 }
            return slashes % 2 == 0
        }
    }

    @discardableResult
    public func replace(_ range: NSRange, with replacement: String) -> Range<Int> {
        let loc = min(range.location, units.count)
        let len = min(range.length, units.count - loc)
        let rep = Array(replacement.utf16)
        let delta = rep.count - len
        let lA = line(containing: loc), lB = line(containing: loc + len)
        let oldBlockEnd = lexStates[lB]
        var delta8 = 0
        if classifier != nil {
            let a8 = utf8Offset(loc), b8 = utf8Offset(loc + len)
            let rep8 = Array(replacement.utf8)
            utf8.replaceSubrange(a8..<b8, with: rep8)
            delta8 = rep8.count - (b8 - a8)
            pendingEdits.append(SourceEdit(range: AbsolutePosition(utf8Offset: a8)..<AbsolutePosition(utf8Offset: b8), replacement: rep8))
            if rep8.count != rep.count { ascii = false }
        }
        units.replaceSubrange(loc..<(loc + len), with: rep)
        let regionStart = lineStarts[lA]
        let regionEnd = lB + 1 < lineStarts.count ? lineStarts[lB + 1] + delta - 1 : units.count
        var starts = [regionStart]
        var i = regionStart
        while i < regionEnd {
            if units[i] == 10 { starts.append(i + 1) }
            i += 1
        }
        let n = starts.count
        lineStarts.replaceSubrange(lA...lB, with: starts)
        if delta != 0 { for k in (lA + n)..<lineStarts.count { lineStarts[k] += delta } }
        lineTokens.replaceSubrange(lA...lB, with: Array(repeating: [], count: n))
        lexStates.replaceSubrange(lA...lB, with: Array(repeating: .initial, count: n))
        eventCache.replaceSubrange(lA...lB, with: Array(repeating: nil, count: n))
        if classifier != nil {
            let starts8 = ascii ? starts : utf8Starts(starts, firstUTF8: lineStarts8[lA])
            lineStarts8.replaceSubrange(lA...lB, with: starts8)
            if delta8 != 0 { for k in (lA + n)..<lineStarts8.count { lineStarts8[k] += delta8 } }
        }
        var state = startState(ofLine: lA)
        lexLines(lA..<(lA + n), state: &state)
        var last = lA + n
        var old = oldBlockEnd
        while last < lineCount, state != old {
            old = lexStates[last]
            lexLines(last..<(last + 1), state: &state)
            last += 1
        }
        lastUpdate = UpdateStats(linesLexed: last - lA, full: false)
        let changed = lineStarts[lA]..<(last < lineCount ? lineStarts[last] : units.count)
        if classifier != nil {
            if let d = parserDirty {
                let lo = d.lowerBound <= loc ? d.lowerBound : max(loc, d.lowerBound + delta)
                let hi = d.upperBound <= loc ? d.upperBound : max(loc + rep.count, d.upperBound + delta)
                parserDirty = min(lo, changed.lowerBound)..<min(units.count, max(hi, changed.upperBound))
            } else {
                parserDirty = changed
            }
        }
        return changed
    }

    private func lexLines(_ lines: Range<Int>, state: inout LexState) {
        guard let lexer else { return }
        var scratch: [SyntaxToken] = []
        units.withUnsafeBufferPointer { buf in
            for n in lines {
                let r = lineRange(n)
                scratch.removeAll(keepingCapacity: true)
                lexer.lex(LineText(units: buf, start: r.lowerBound, end: r.upperBound), state: &state, into: &scratch)
                let s = r.lowerBound
                lineTokens[n] = scratch.map { SyntaxToken(kind: $0.kind, location: $0.location - s, length: $0.length) }
                lexStates[n] = state
                eventCache[n] = nil
            }
        }
    }

    private func classifyLines(_ lines: Range<Int>) {
        guard let classifier, !lines.isEmpty else { return }
        for n in lines { lineTokens[n] = []; eventCache[n] = nil }
        let a8 = lineStarts8[lines.lowerBound]
        let b8 = lines.upperBound < lineStarts8.count ? lineStarts8[lines.upperBound] : utf8.count
        var ranges: [(SyntaxTokenKind, Int, Int)] = []
        classifier.classify(a8..<b8, source: utf8, into: &ranges)
        var n = lines.lowerBound
        for (kind, s8, e8) in ranges {
            let s = utf16Offset(s8), e = utf16Offset(e8)
            while n + 1 < lines.upperBound, lineStarts[n + 1] <= s { n += 1 }
            var k = n
            while k < lines.upperBound {
                let r = lineRange(k)
                let ls = lineStarts[k]
                if e <= ls && k > n { break }
                let ps = max(s, ls), pe = min(e, r.upperBound)
                if pe > ps { lineTokens[k].append(SyntaxToken(kind: kind, location: ps - ls, length: pe - ps)) }
                if e <= r.upperBound { break }
                k += 1
            }
        }
    }

    private func utf8Starts(_ starts: [Int], firstUTF8: Int = 0) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(starts.count)
        var o8 = firstUTF8
        var i = starts.first ?? 0
        for s in starts {
            while i < s { o8 += utf8Length(at: &i) }
            out.append(o8)
        }
        return out
    }

    @inline(__always) private func utf8Length(at i: inout Int) -> Int {
        let u = units[i]
        i += 1
        if u < 0x80 { return 1 }
        if u < 0x800 { return 2 }
        if u >= 0xD800, u < 0xDC00, i < units.count, units[i] >= 0xDC00, units[i] < 0xE000 { i += 1; return 4 }
        return 3
    }

    private func utf8Offset(_ o16: Int) -> Int {
        if ascii { return o16 }
        let n = line(containing: o16)
        var i = lineStarts[n]
        var o8 = lineStarts8[n]
        while i < o16 { o8 += utf8Length(at: &i) }
        return o8
    }

    private func utf16Offset(_ o8: Int) -> Int {
        if ascii { return o8 }
        var lo = 0, hi = lineStarts8.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts8[mid] <= o8 { lo = mid } else { hi = mid - 1 }
        }
        var i = lineStarts[lo]
        var c8 = lineStarts8[lo]
        while c8 < o8, i < units.count { c8 += utf8Length(at: &i) }
        return i
    }
}
