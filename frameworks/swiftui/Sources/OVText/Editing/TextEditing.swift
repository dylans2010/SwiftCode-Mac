public struct TextSelectionRange: Hashable, Sendable {
    public var anchor: Int
    public var head: Int

    public init(anchor: Int, head: Int) {
        self.anchor = anchor
        self.head = head
    }

    public init(caret: Int) { self.init(anchor: caret, head: caret) }

    public var range: Range<Int> { min(anchor, head)..<max(anchor, head) }
    public var isEmpty: Bool { anchor == head }
}

public enum TextMovement: Hashable, Sendable {
    case character
    case word
    case line
    case paragraph
    case document
}

public protocol TextEditingLayout {
    func verticalMove(from offset: Int, lines: Int, x: Double?) -> (offset: Int, x: Double)?
    func lineBoundary(of offset: Int, end: Bool) -> Int
}

public final class TextEditingModel {
    public private(set) var characters: [Character]
    public private(set) var selection = TextSelectionRange(caret: 0)
    public private(set) var markedText = ""
    public private(set) var markedCursor = 0
    public var allowsNewlines: Bool
    public var layout: (any TextEditingLayout)?
    public private(set) var revision = 0

    private struct Edit {
        var range: Range<Int>
        var removed: [Character]
        var inserted: [Character]
        var selectionBefore: TextSelectionRange
        var selectionAfter: TextSelectionRange
        var kind: Kind
        enum Kind { case typing, deleteBackward, deleteForward, other }
    }

    private var undoStack: [[Edit]] = []
    private var redoStack: [[Edit]] = []
    private var openGroup: Edit.Kind?
    private var goalX: Double?
    public var undoLimit = 200

    public init(text: String = "", allowsNewlines: Bool = false) {
        characters = Array(text)
        self.allowsNewlines = allowsNewlines
        selection = TextSelectionRange(caret: characters.count)
    }

    public var text: String { String(characters) }
    public var count: Int { characters.count }
    public var caret: Int { selection.head }
    public var selectedRange: Range<Int> { selection.range }
    public var selectedText: String { String(characters[selection.range]) }
    public var hasMarkedText: Bool { !markedText.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var displayCharacters: [Character] {
        guard hasMarkedText else { return characters }
        var c = characters
        c.insert(contentsOf: Array(markedText), at: min(selection.range.lowerBound, c.count))
        return c
    }

    public var displayMarkedRange: Range<Int>? {
        guard hasMarkedText else { return nil }
        let s = min(selection.range.lowerBound, characters.count)
        return s..<(s + markedText.count)
    }

    public var displayCaret: Int {
        guard hasMarkedText else { return selection.head }
        return min(selection.range.lowerBound, characters.count) + markedCursor
    }

    public func setText(_ s: String) {
        let new = Array(s)
        guard new != characters else { return }
        characters = new
        selection = TextSelectionRange(anchor: min(selection.anchor, new.count), head: min(selection.head, new.count))
        markedText = ""
        markedCursor = 0
        undoStack.removeAll()
        redoStack.removeAll()
        openGroup = nil
        revision += 1
    }

    public func setSelection(_ s: TextSelectionRange) {
        let c = TextSelectionRange(anchor: clamp(s.anchor), head: clamp(s.head))
        if c != selection { breakUndoGroup() }
        selection = c
        goalX = nil
    }

    public func setCaret(_ offset: Int) { setSelection(TextSelectionRange(caret: offset)) }

    public func extendSelection(to offset: Int) {
        setSelection(TextSelectionRange(anchor: selection.anchor, head: offset))
    }

    public func selectAll() { setSelection(TextSelectionRange(anchor: 0, head: characters.count)) }

    public func wordRange(at offset: Int) -> Range<Int> {
        let n = characters.count
        guard n > 0 else { return 0..<0 }
        var i = min(max(offset, 0), n - 1)
        if offset == n || (offset > 0 && Self.kind(characters[i]) == .space && Self.kind(characters[offset - 1]) == .word) {
            i = max(0, offset - 1)
        }
        let k = Self.kind(characters[i])
        if k == .punctuation { return i..<(i + 1) }
        if k == .newline { return i..<(i + 1) }
        var lo = i, hi = i + 1
        while lo > 0 && Self.kind(characters[lo - 1]) == k { lo -= 1 }
        while hi < n && Self.kind(characters[hi]) == k { hi += 1 }
        return lo..<hi
    }

    public func paragraphRange(at offset: Int) -> Range<Int> {
        let n = characters.count
        var lo = min(max(offset, 0), n)
        while lo > 0 && !characters[lo - 1].isNewline { lo -= 1 }
        var hi = lo
        while hi < n && !characters[hi].isNewline { hi += 1 }
        if hi < n { hi += 1 }
        return lo..<hi
    }

    public func selectWord(at offset: Int) {
        let r = wordRange(at: offset)
        setSelection(TextSelectionRange(anchor: r.lowerBound, head: r.upperBound))
    }

    public func selectParagraph(at offset: Int) {
        let r = paragraphRange(at: offset)
        setSelection(TextSelectionRange(anchor: r.lowerBound, head: r.upperBound))
    }

    public func move(_ movement: TextMovement, forward: Bool, extending: Bool = false) {
        let from = selection.head
        var to: Int
        if !extending && !selection.isEmpty && movement == .character {
            to = forward ? selection.range.upperBound : selection.range.lowerBound
        } else {
            to = target(of: movement, from: from, forward: forward)
        }
        to = clamp(to)
        setSelection(extending ? TextSelectionRange(anchor: selection.anchor, head: to) : TextSelectionRange(caret: to))
    }

    public func moveVertically(lines: Int, extending: Bool = false) {
        let from = selection.head
        var to: Int
        var x = goalX
        if let layout {
            if let r = layout.verticalMove(from: from, lines: lines, x: goalX) {
                to = r.offset
                x = r.x
            } else {
                to = lines < 0 ? 0 : characters.count
            }
        } else if allowsNewlines {
            to = logicalVerticalMove(from: from, lines: lines)
        } else {
            to = lines < 0 ? 0 : characters.count
        }
        to = clamp(to)
        setSelection(extending ? TextSelectionRange(anchor: selection.anchor, head: to) : TextSelectionRange(caret: to))
        goalX = x
    }

    private func logicalVerticalMove(from: Int, lines: Int) -> Int {
        var start = from
        while start > 0 && !characters[start - 1].isNewline { start -= 1 }
        let column = from - start
        var p = start
        if lines < 0 {
            for _ in 0..<(-lines) {
                guard p > 0 else { return 0 }
                p -= 1
                while p > 0 && !characters[p - 1].isNewline { p -= 1 }
            }
        } else {
            for _ in 0..<lines {
                while p < characters.count && !characters[p].isNewline { p += 1 }
                guard p < characters.count else { return characters.count }
                p += 1
            }
        }
        var end = p
        while end < characters.count && !characters[end].isNewline { end += 1 }
        return min(p + column, end)
    }

    public func target(of movement: TextMovement, from offset: Int, forward: Bool) -> Int {
        let n = characters.count
        switch movement {
        case .character:
            return forward ? min(n, offset + 1) : max(0, offset - 1)
        case .word:
            return forward ? nextWordEnd(from: offset) : previousWordStart(from: offset)
        case .line:
            if let layout { return layout.lineBoundary(of: offset, end: forward) }
            fallthrough
        case .paragraph:
            if forward {
                var i = offset
                while i < n && !characters[i].isNewline { i += 1 }
                return i
            }
            var i = offset
            while i > 0 && !characters[i - 1].isNewline { i -= 1 }
            return i
        case .document:
            return forward ? n : 0
        }
    }

    private enum CharKind { case word, space, newline, punctuation }

    private static func kind(_ c: Character) -> CharKind {
        if c.isNewline { return .newline }
        if c.isWhitespace { return .space }
        if c.isLetter || c.isNumber || c == "_" { return .word }
        return .punctuation
    }

    private func nextWordEnd(from offset: Int) -> Int {
        let n = characters.count
        var i = offset
        while i < n && Self.kind(characters[i]) != .word && Self.kind(characters[i]) != .punctuation { i += 1 }
        guard i < n else { return n }
        if Self.kind(characters[i]) == .punctuation {
            let p = characters[i]
            while i < n && characters[i] == p { i += 1 }
            return i
        }
        while i < n && Self.kind(characters[i]) == .word { i += 1 }
        return i
    }

    private func previousWordStart(from offset: Int) -> Int {
        var i = offset
        while i > 0 && Self.kind(characters[i - 1]) != .word && Self.kind(characters[i - 1]) != .punctuation { i -= 1 }
        guard i > 0 else { return 0 }
        if Self.kind(characters[i - 1]) == .punctuation {
            let p = characters[i - 1]
            while i > 0 && characters[i - 1] == p { i -= 1 }
            return i
        }
        while i > 0 && Self.kind(characters[i - 1]) == .word { i -= 1 }
        return i
    }

    public func insert(_ s: String) {
        let piece = filtered(s)
        markedText = ""
        markedCursor = 0
        let typed = piece.count <= 2 && !piece.contains(where: \.isNewline)
        if !selection.isEmpty { breakUndoGroup() }
        replace(selection.range, with: piece, kind: typed ? .typing : .other)
    }

    public func paste(_ s: String) {
        breakUndoGroup()
        markedText = ""
        replace(selection.range, with: filtered(s), kind: .other)
        breakUndoGroup()
    }

    public func deleteBackward(_ movement: TextMovement = .character) {
        if !selection.isEmpty {
            replace(selection.range, with: [], kind: .other)
            breakUndoGroup()
            return
        }
        let from = target(of: movement, from: selection.head, forward: false)
        guard from < selection.head else { return }
        replace(from..<selection.head, with: [], kind: movement == .character ? .deleteBackward : .other)
    }

    public func deleteForward(_ movement: TextMovement = .character) {
        if !selection.isEmpty {
            replace(selection.range, with: [], kind: .other)
            breakUndoGroup()
            return
        }
        let to = target(of: movement, from: selection.head, forward: true)
        guard to > selection.head else { return }
        replace(selection.head..<to, with: [], kind: movement == .character ? .deleteForward : .other)
    }

    public func copy() -> String? { selection.isEmpty ? nil : selectedText }

    public func cut() -> String? {
        guard !selection.isEmpty else { return nil }
        let s = selectedText
        breakUndoGroup()
        replace(selection.range, with: [], kind: .other)
        breakUndoGroup()
        return s
    }

    public func replace(_ range: Range<Int>, with string: String) {
        breakUndoGroup()
        replace(range, with: filtered(string), kind: .other)
        breakUndoGroup()
    }

    public func setMarkedText(_ s: String, cursor: Int) {
        if !s.isEmpty && markedText.isEmpty && !selection.isEmpty {
            replace(selection.range, with: [], kind: .other)
        }
        markedText = s
        markedCursor = min(max(0, cursor), s.count)
    }

    public func unmarkText() {
        markedText = ""
        markedCursor = 0
    }

    public func undo() {
        unmarkText()
        guard let group = undoStack.popLast() else { return }
        for e in group.reversed() {
            characters.replaceSubrange(e.range, with: e.removed)
            selection = e.selectionBefore
        }
        redoStack.append(group)
        openGroup = nil
        goalX = nil
        revision += 1
    }

    public func redo() {
        unmarkText()
        guard let group = redoStack.popLast() else { return }
        for e in group {
            let start = e.range.lowerBound
            characters.replaceSubrange(start..<(start + e.removed.count), with: e.inserted)
            selection = e.selectionAfter
        }
        undoStack.append(group)
        openGroup = nil
        goalX = nil
        revision += 1
    }

    public func breakUndoGroup() { openGroup = nil }

    private func clamp(_ i: Int) -> Int { min(max(0, i), characters.count) }

    private func filtered(_ s: String) -> [Character] {
        if allowsNewlines { return Array(s) }
        return s.map { $0.isNewline ? " " : $0 }
    }

    private func replace(_ range: Range<Int>, with new: [Character], kind: Edit.Kind) {
        let r = clamp(range.lowerBound)..<clamp(range.upperBound)
        guard !(r.isEmpty && new.isEmpty) else { return }
        let before = selection
        let removed = Array(characters[r])
        characters.replaceSubrange(r, with: new)
        let caret = r.lowerBound + new.count
        selection = TextSelectionRange(caret: caret)
        goalX = nil
        revision += 1
        let edit = Edit(range: r.lowerBound..<caret, removed: removed, inserted: new, selectionBefore: before,
                        selectionAfter: selection, kind: kind)
        redoStack.removeAll()
        if let open = openGroup, open == kind, kind != .other, var group = undoStack.popLast(), let last = group.last,
           Self.continues(last, edit) {
            group.append(edit)
            undoStack.append(group)
        } else {
            undoStack.append([edit])
            if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        }
        openGroup = kind == .other ? nil : kind
    }

    private static func continues(_ a: Edit, _ b: Edit) -> Bool {
        switch b.kind {
        case .typing: return b.range.lowerBound == a.range.upperBound
        case .deleteBackward: return b.range.lowerBound + b.removed.count == a.range.lowerBound
        case .deleteForward: return b.range.lowerBound == a.range.lowerBound
        case .other: return false
        }
    }
}

public struct TextLayoutGeometry: TextEditingLayout {
    public struct LineBox: Sendable {
        public var range: Range<Int>
        public var x: Double
        public var top: Double
        public var height: Double
        public var baseline: Double
        public var edges: [Double]
        public var width: Double
    }

    public let lines: [LineBox]
    public let count: Int

    public init(layout: TextLayout, lineOrigins: [Double]? = nil, baselines: [Double]? = nil,
                emptyLineHeight: Double = 20, emptyAscent: Double = 16) {
        let clusters = layout.clusters
        count = clusters.count
        var out: [LineBox] = []
        func isBreak(_ i: Int) -> Bool {
            let b = clusters[i].breakClass
            return b == .BK || b == .CR || b == .LF || b == .NL
        }
        for (k, line) in layout.lines.enumerated() {
            var range = line.range
            if !range.isEmpty, isBreak(range.upperBound - 1) { range = range.lowerBound..<(range.upperBound - 1) }
            var xs = [Double](repeating: 0, count: range.count + 1)
            var x = 0.0
            var order = line.visualOrder.filter { range.contains($0) }
            if order.count != range.count { order = Array(range) }
            let rtl = line.direction == .rightToLeft
            for idx in order {
                let c = clusters[idx]
                let w = c.advance + c.kernAfter
                if rtl { xs[idx - range.lowerBound] = x + w } else { xs[idx - range.lowerBound] = x }
                x += w
            }
            xs[range.count] = rtl ? 0 : x
            let lineX = lineOrigins.map { $0.indices.contains(k) ? $0[k] : 0 } ?? 0
            if line.ascent + line.descent <= 0 {
                out.append(LineBox(range: range, x: lineX, top: line.top, height: emptyLineHeight,
                                   baseline: line.top + emptyAscent, edges: xs, width: line.width))
                continue
            }
            let baseline = baselines.map { $0.indices.contains(k) ? $0[k] : line.baseline } ?? line.baseline
            out.append(LineBox(range: range, x: lineX, top: baseline - line.ascent, height: line.ascent + line.descent,
                               baseline: baseline, edges: xs, width: line.width))
        }
        if out.isEmpty {
            out.append(LineBox(range: 0..<0, x: lineOrigins?.first ?? 0, top: 0, height: emptyLineHeight,
                               baseline: emptyAscent, edges: [0], width: 0))
        }
        if let last = layout.lines.last, !last.range.isEmpty, isBreak(last.range.upperBound - 1),
           let lb = out.last {
            let pitch = last.ascent + last.descent + last.leading
            out.append(LineBox(range: count..<count, x: 0, top: lb.top + pitch, height: lb.height, baseline: lb.baseline + pitch,
                               edges: [0], width: 0))
        }
        lines = out
    }

    public func lineIndex(of offset: Int) -> Int {
        for (k, l) in lines.enumerated() {
            if offset < l.range.upperBound && offset >= l.range.lowerBound { return k }
            if offset == l.range.upperBound {
                if k + 1 < lines.count, lines[k + 1].range.lowerBound == offset, lines[k + 1].range.upperBound > offset || l.range.upperBound == l.range.lowerBound {
                    continue
                }
                return k
            }
        }
        return max(0, lines.count - 1)
    }

    public func caretX(_ offset: Int, line k: Int) -> Double {
        let l = lines[k]
        let i = min(max(offset - l.range.lowerBound, 0), l.edges.count - 1)
        return l.x + l.edges[i]
    }

    public func caret(at offset: Int) -> (x: Double, top: Double, height: Double) {
        let k = lineIndex(of: offset)
        return (caretX(offset, line: k), lines[k].top, lines[k].height)
    }

    public func offset(atX x: Double, y: Double) -> Int {
        var k = 0
        for (i, l) in lines.enumerated() where y >= l.top { k = i }
        return offset(atX: x, line: k)
    }

    public func offset(atX x: Double, line k: Int) -> Int {
        let l = lines[k]
        guard !l.range.isEmpty else { return l.range.lowerBound }
        var best = l.range.lowerBound
        var bestD = Double.infinity
        for i in 0..<l.edges.count {
            let d = abs(l.x + l.edges[i] - x)
            if d < bestD {
                bestD = d
                best = l.range.lowerBound + i
            }
        }
        return best
    }

    public func selectionRects(_ range: Range<Int>) -> [(x: Double, top: Double, width: Double, height: Double)] {
        guard !range.isEmpty else { return [] }
        var out: [(Double, Double, Double, Double)] = []
        for (k, l) in lines.enumerated() {
            let lo = max(range.lowerBound, l.range.lowerBound)
            let hi = min(range.upperBound, l.range.upperBound)
            var a: Double, b: Double
            if lo < hi {
                a = caretX(lo, line: k)
                b = caretX(hi, line: k)
                if a > b { swap(&a, &b) }
            } else if l.range.isEmpty && range.contains(l.range.lowerBound) && l.range.lowerBound < count {
                a = l.x
                b = l.x
            } else {
                continue
            }
            let nextStart = k + 1 < lines.count ? lines[k + 1].range.lowerBound : count
            if range.upperBound > l.range.upperBound && l.range.upperBound < nextStart { b += 4 }
            out.append((a, l.top, max(0, b - a), l.height))
        }
        return out
    }

    public func verticalMove(from offset: Int, lines delta: Int, x: Double?) -> (offset: Int, x: Double)? {
        let k = lineIndex(of: offset)
        let goal = x ?? caretX(offset, line: k)
        let t = k + delta
        guard lines.indices.contains(t) else { return nil }
        return (self.offset(atX: goal, line: t), goal)
    }

    public func lineBoundary(of offset: Int, end: Bool) -> Int {
        let l = lines[lineIndex(of: offset)]
        return end ? l.range.upperBound : l.range.lowerBound
    }
}
