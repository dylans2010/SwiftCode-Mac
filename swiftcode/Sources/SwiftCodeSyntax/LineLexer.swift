public struct LexState: Hashable, Sendable {
    public var open: SyntaxTokenKind?
    public var mode: UInt8
    public var depth: Int32
    public var aux: Int32
    public var delimiter: [UInt16]

    public init(open: SyntaxTokenKind? = nil, mode: UInt8 = 0, depth: Int32 = 0, aux: Int32 = 0, delimiter: [UInt16] = []) {
        self.open = open
        self.mode = mode
        self.depth = depth
        self.aux = aux
        self.delimiter = delimiter
    }

    public static let initial = LexState()
}

public struct LineText {
    public let units: UnsafeBufferPointer<UInt16>
    public let start: Int
    public let end: Int

    @inline(__always) public subscript(_ i: Int) -> UInt16 { i >= start && i < end ? units[i] : 0 }

    @inline(__always) func matches(_ ascii: StaticString, at i: Int) -> Bool {
        let n = ascii.utf8CodeUnitCount
        guard i + n <= end else { return false }
        return ascii.withUTF8Buffer { b in
            for k in 0..<n where units[i + k] != UInt16(b[k]) { return false }
            return true
        }
    }

    func find(_ ascii: StaticString, from i: Int) -> Int? {
        var j = i
        let n = ascii.utf8CodeUnitCount
        while j + n <= end {
            if matches(ascii, at: j) { return j }
            j += 1
        }
        return nil
    }

    func firstNonSpace(from i: Int) -> Int {
        var j = i
        while j < end, units[j] == 32 || units[j] == 9 { j += 1 }
        return j
    }

    func string(_ a: Int, _ b: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: units[a..<b]), as: UTF16.self)
    }

    func word(_ a: Int, _ b: Int, in set: Set<String>) -> Bool {
        guard b - a <= 24 else { return false }
        return set.contains(string(a, b))
    }

    var isBlank: Bool { firstNonSpace(from: start) == end }
}

public protocol LineLexer: Sendable {
    func lex(_ line: LineText, state: inout LexState, into tokens: inout [SyntaxToken])
}

@inline(__always) func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
@inline(__always) func isHexDigit(_ c: UInt16) -> Bool { isDigit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102) }
@inline(__always) func isUpper(_ c: UInt16) -> Bool { c >= 65 && c <= 90 }
@inline(__always) func isIdentStart(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127 }
@inline(__always) func isIdentPart(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }
@inline(__always) func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 }

extension Array where Element == SyntaxToken {
    @inline(__always) mutating func add(_ kind: SyntaxTokenKind, _ a: Int, _ b: Int) {
        if b > a { append(SyntaxToken(kind: kind, location: a, length: b - a)) }
    }
}

func placeholderEnd(_ l: LineText, _ i: Int) -> Int? {
    guard l[i] == 60, l[i + 1] == 35 else { return nil }
    var j = i + 2
    while j + 1 < l.end {
        if l[j] == 35 && l[j + 1] == 62 { return j > i + 2 ? j + 2 : nil }
        j += 1
    }
    return nil
}

func numberEnd(_ l: LineText, _ i: Int, separator: UInt16 = 95) -> Int {
    var j = i
    let hex = l[i] == 48 && (l[i + 1] == 120 || l[i + 1] == 88)
    while j < l.end {
        let c = l[j]
        if isIdentPart(c) || c == separator {
            if (!hex && (c == 101 || c == 69)) || (hex && (c == 112 || c == 80)), l[j + 1] == 43 || l[j + 1] == 45, isDigit(l[j + 2]) { j += 2 }
            j += 1
        } else if c == 46, isDigit(l[j + 1]) {
            j += 1
        } else {
            break
        }
    }
    return j
}

public enum SyntaxLexers {
    public static func lexer(for language: SyntaxLanguage) -> (any LineLexer)? {
        switch language {
        case .swift: SwiftLineLexer()
        case .c, .cpp, .objc, .metal: CFamilyLexer(dialect: language)
        case .json: JSONLexer()
        case .xml: XMLLexer()
        case .markdown: MarkdownLexer()
        case .yaml: YAMLLexer()
        case .shell: ShellLexer()
        case .xcconfig: XcconfigLexer()
        case .plain: nil
        }
    }

    public static func tokens(in text: String, language: SyntaxLanguage) -> [SyntaxToken] {
        guard let lexer = lexer(for: language) else { return [] }
        let units = Array(text.utf16)
        return units.withUnsafeBufferPointer { buf in
            var out: [SyntaxToken] = []
            out.reserveCapacity(units.count / 6)
            var state = LexState.initial
            var lineStart = 0
            var open: SyntaxToken?
            var scratch: [SyntaxToken] = []
            while lineStart <= buf.count {
                var lineEnd = lineStart
                while lineEnd < buf.count, buf[lineEnd] != 10 { lineEnd += 1 }
                let contentEnd = lineEnd > lineStart && buf[lineEnd - 1] == 13 ? lineEnd - 1 : lineEnd
                scratch.removeAll(keepingCapacity: true)
                lexer.lex(LineText(units: buf, start: lineStart, end: contentEnd), state: &state, into: &scratch)
                var k = 0
                if var o = open {
                    open = nil
                    if let first = scratch.first, first.location == lineStart, first.kind == o.kind {
                        o.length = first.end - o.location
                        k = 1
                    }
                    if k == scratch.count, state.open == o.kind {
                        open = o
                    } else {
                        out.append(o)
                    }
                }
                if k < scratch.count {
                    out.append(contentsOf: scratch[k...])
                    if let o = state.open, let last = out.last, last.kind == o, last.end == contentEnd { open = out.removeLast() }
                }
                if lineEnd >= buf.count { break }
                lineStart = lineEnd + 1
            }
            if let o = open { out.append(o) }
            return out
        }
    }
}
