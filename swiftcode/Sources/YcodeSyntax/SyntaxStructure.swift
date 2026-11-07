import Foundation

public struct BlockEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bracket(UInt16)
        case tag
        case keyword
    }
    public var kind: Kind
    public var isOpen: Bool
    public var offset: Int

    public init(kind: Kind, isOpen: Bool, offset: Int) {
        self.kind = kind
        self.isOpen = isOpen
        self.offset = offset
    }
}

public struct SyntaxBlock: Equatable, Sendable {
    public var startLine: Int
    public var endLine: Int
    public var depth: Int

    public init(startLine: Int, endLine: Int, depth: Int) {
        self.startLine = startLine
        self.endLine = endLine
        self.depth = depth
    }
}

extension SyntaxDocument {
    static let shellOpeners: Set<String> = ["then", "do", "case"]
    static let shellClosers: Set<String> = ["fi", "done", "esac"]

    public func blockEvents(onLine n: Int) -> [BlockEvent] {
        let s = lineStart(n)
        if let cached = eventCache[n] { return cached.map { BlockEvent(kind: $0.kind, isOpen: $0.isOpen, offset: $0.offset + s) } }
        let events = computeBlockEvents(onLine: n)
        eventCache[n] = events.map { BlockEvent(kind: $0.kind, isOpen: $0.isOpen, offset: $0.offset - s) }
        return events
    }

    private func computeBlockEvents(onLine n: Int) -> [BlockEvent] {
        let r = lineRange(n)
        guard !r.isEmpty else { return [] }
        let toks = tokens(onLine: n)
        var out: [BlockEvent] = []
        switch language {
        case .xml:
            for t in toks where t.kind == .tagName {
                let lt = t.location - 1
                guard lt >= 0 else { continue }
                if units[lt] == 47 {
                    out.append(BlockEvent(kind: .tag, isOpen: false, offset: lt - 1))
                } else if units[lt] == 60, !isSelfClosing(after: t.end) {
                    out.append(BlockEvent(kind: .tag, isOpen: true, offset: lt))
                }
            }
            return out
        case .shell:
            for t in toks where t.kind == .keyword {
                let w = String(decoding: units[t.location..<t.end], as: UTF16.self)
                if Self.shellOpeners.contains(w) { out.append(BlockEvent(kind: .keyword, isOpen: true, offset: t.location)) }
                else if Self.shellClosers.contains(w) { out.append(BlockEvent(kind: .keyword, isOpen: false, offset: t.location)) }
                else if w == "else" {
                    out.append(BlockEvent(kind: .keyword, isOpen: false, offset: t.location))
                    out.append(BlockEvent(kind: .keyword, isOpen: true, offset: t.location))
                } else if w == "elif" {
                    out.append(BlockEvent(kind: .keyword, isOpen: false, offset: t.location))
                }
            }
            var k = 0
            for i in r {
                while k < toks.count, toks[k].end <= i { k += 1 }
                if k < toks.count, toks[k].location <= i, toks[k].kind.isCommentOrString || toks[k].kind == .variable { continue }
                if units[i] == 123 { out.append(BlockEvent(kind: .bracket(123), isOpen: true, offset: i)) }
                else if units[i] == 125 { out.append(BlockEvent(kind: .bracket(123), isOpen: false, offset: i)) }
            }
            return out.sorted { $0.offset < $1.offset || ($0.offset == $1.offset && !$0.isOpen && $1.isOpen) }
        case .markdown:
            return []
        default:
            var k = 0
            let masksPreprocessor = language.isCFamily
            for i in r {
                let u = units[i]
                guard u == 40 || u == 41 || u == 91 || u == 93 || u == 123 || u == 125 else { continue }
                while k < toks.count, toks[k].end <= i { k += 1 }
                if k < toks.count, toks[k].location <= i {
                    let kind = toks[k].kind
                    if kind.isCommentOrString || kind == .placeholder || kind == .attribute && language.isCFamily || (masksPreprocessor && kind == .preprocessor) { continue }
                }
                switch u {
                case 40: out.append(BlockEvent(kind: .bracket(40), isOpen: true, offset: i))
                case 91: out.append(BlockEvent(kind: .bracket(91), isOpen: true, offset: i))
                case 123: out.append(BlockEvent(kind: .bracket(123), isOpen: true, offset: i))
                case 41: out.append(BlockEvent(kind: .bracket(40), isOpen: false, offset: i))
                case 93: out.append(BlockEvent(kind: .bracket(91), isOpen: false, offset: i))
                default: out.append(BlockEvent(kind: .bracket(123), isOpen: false, offset: i))
                }
            }
            return out
        }
    }

    private func isSelfClosing(after i: Int) -> Bool {
        var j = i
        var quote: UInt16 = 0
        while j < units.count, j - i < 4000 {
            let u = units[j]
            if quote != 0 { if u == quote { quote = 0 } }
            else if u == 34 || u == 39 { quote = u }
            else if u == 62 { return j > i && units[j - 1] == 47 }
            else if u == 60 { return false }
            j += 1
        }
        return false
    }

    public func enclosingOpener(before offset: Int, limit: Int = 5_000) -> (event: BlockEvent, line: Int)? {
        var pending = 0
        var n = line(containing: offset)
        let stop = max(0, n - limit)
        while n >= stop {
            for e in blockEvents(onLine: n).reversed() where e.offset < offset {
                if !e.isOpen { pending += 1 }
                else if pending > 0 { pending -= 1 }
                else { return (e, n) }
            }
            n -= 1
        }
        return nil
    }

    public func matchingBracket(at offset: Int, limit: Int = 5_000) -> Int? {
        let n = line(containing: offset)
        guard let e = blockEvents(onLine: n).first(where: { $0.offset == offset }), case .bracket = e.kind else { return nil }
        var depth = 0
        if e.isOpen {
            var k = n
            while k < lineCount, k - n <= limit {
                for f in blockEvents(onLine: k) where f.offset > offset && f.kind == e.kind {
                    if f.isOpen { depth += 1 } else if depth == 0 { return f.offset } else { depth -= 1 }
                }
                k += 1
            }
        } else {
            var k = n
            while k >= 0, n - k <= limit {
                for f in blockEvents(onLine: k).reversed() where f.offset < offset && f.kind == e.kind {
                    if !f.isOpen { depth += 1 } else if depth == 0 { return f.offset } else { depth -= 1 }
                }
                k -= 1
            }
        }
        return nil
    }

    public func blocks() -> [SyntaxBlock] {
        var stack: [(BlockEvent, Int)] = []
        var out: [SyntaxBlock] = []
        for n in 0..<lineCount {
            for e in blockEvents(onLine: n) {
                if e.isOpen { stack.append((e, n)); continue }
                guard let i = stack.lastIndex(where: { $0.0.kind == e.kind }) else { continue }
                let (_, start) = stack[i]
                stack.removeSubrange(i...)
                if n > start { out.append(SyntaxBlock(startLine: start, endLine: n, depth: i)) }
            }
        }
        return out.sorted { ($0.startLine, $0.depth) < ($1.startLine, $1.depth) }
    }
}
