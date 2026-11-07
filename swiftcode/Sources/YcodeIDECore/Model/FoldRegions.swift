import Foundation

public struct FoldRegion: Equatable, Hashable, Sendable {
    public enum Kind: Sendable, Hashable { case braces, comment }

    public var startLine: Int
    public var endLine: Int
    public var depth: Int
    public var kind: Kind

    public init(startLine: Int, endLine: Int, depth: Int, kind: Kind = .braces) {
        self.startLine = startLine
        self.endLine = endLine
        self.depth = depth
        self.kind = kind
    }

    public var hiddenLines: ClosedRange<Int> {
        kind == .comment ? (startLine + 1)...endLine : (startLine + 1)...(endLine - 1)
    }
    public func contains(line: Int) -> Bool { line >= startLine && line <= endLine }
}

public enum FoldRegions {
    static func code(_ text: String, language: SourceTokenizer.Language) -> [UInt16] {
        var units = Array(text.utf16)
        for t in SourceTokenizer(language: language).tokens(in: text) where [.comment, .docComment, .string, .preprocessor].contains(t.kind) {
            for i in t.range.location..<min(NSMaxRange(t.range), units.count) where units[i] != 10 { units[i] = 32 }
        }
        return units
    }

    public static func regions(in text: String, language: SourceTokenizer.Language) -> [FoldRegion] {
        guard language != .plain else { return [] }
        let units = code(text, language: language)
        let index = LineIndex(String(decoding: units, as: UTF16.self))
        var stack: [Int] = []
        var out: [FoldRegion] = []
        for (i, u) in units.enumerated() {
            if u == 123 { stack.append(i) }
            else if u == 125, let open = stack.popLast() {
                let a = index.line(at: open), b = index.line(at: i)
                if b - a >= 2 { out.append(FoldRegion(startLine: a, endLine: b, depth: stack.count)) }
            }
        }
        return out.sorted { ($0.startLine, -$0.endLine) < ($1.startLine, -$1.endLine) }
    }

    public static func innermost(_ regions: [FoldRegion], containing line: Int) -> FoldRegion? {
        regions.filter { $0.contains(line: line) }.max { $0.depth < $1.depth }
    }

    public static func functionRegions(in text: String, language: SourceTokenizer.Language) -> [FoldRegion] {
        let all = regions(in: text, language: language)
        guard !all.isEmpty else { return [] }
        let lines = String(decoding: code(text, language: language), as: UTF16.self).components(separatedBy: "\n")
        return all.filter { r in
            guard r.startLine >= 1, r.startLine <= lines.count else { return false }
            var header = lines[r.startLine - 1]
            if let brace = header.firstIndex(of: "{") { header = String(header[..<brace]) }
            var l = r.startLine - 1
            while !isFunctionHeader(header, language: language), l >= 1, r.startLine - l <= 8 {
                let prev = lines[l - 1].trimmingCharacters(in: .whitespaces)
                if prev.isEmpty || prev.hasSuffix("}") || prev.hasSuffix("{") || prev.hasSuffix(";") { break }
                header = prev + " " + header
                l -= 1
            }
            return isFunctionHeader(header, language: language)
        }
    }

    static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "@") }).map(String.init)
    }

    static func isFunctionHeader(_ header: String, language: SourceTokenizer.Language) -> Bool {
        let h = header.trimmingCharacters(in: .whitespaces)
        let w = words(h)
        switch language {
        case .swift:
            if w.contains("func") || w.contains("deinit") || w.contains("subscript") { return true }
            if w.contains("init"), h.contains("("), !h.contains(".init") { return true }
            if let first = w.first, ["get", "set", "willSet", "didSet", "_read", "_modify"].contains(first), w.count <= 3 { return true }
            if w.contains("var"), h.contains(":"), !h.contains("=") { return true }
            return false
        case .objc, .c, .cpp, .metal:
            if h.hasPrefix("-") || h.hasPrefix("+") { return true }
            guard h.hasSuffix(")") else { return false }
            let control: Set<String> = ["if", "for", "while", "switch", "do", "else", "catch", "return", "@synchronized", "@autoreleasepool", "@try", "@catch", "@finally"]
            guard let first = w.first, !control.contains(first) else { return false }
            return w.count >= 2 && !h.contains("=") && !h.contains("^")
        default:
            return false
        }
    }

    public static func commentRegions(in text: String, language: SourceTokenizer.Language) -> [FoldRegion] {
        guard language != .plain else { return [] }
        let index = LineIndex(text)
        let ns = text as NSString
        var out: [FoldRegion] = []
        var lineComments = Set<Int>()
        for t in SourceTokenizer(language: language).tokens(in: text) where t.kind == .comment || t.kind == .docComment {
            let s = ns.substring(with: t.range)
            let a = index.line(at: t.range.location)
            if s.hasPrefix("/*") {
                let b = index.line(at: max(t.range.location, NSMaxRange(t.range) - 1))
                if b > a { out.append(FoldRegion(startLine: a, endLine: b, depth: 0, kind: .comment)) }
            } else if let r = index.range(ofLine: a),
                      ns.substring(with: NSRange(location: r.location, length: t.range.location - r.location)).allSatisfy({ $0 == " " || $0 == "\t" }) {
                lineComments.insert(a)
            }
        }
        var run: [Int] = []
        func flush() {
            if run.count >= 3 { out.append(FoldRegion(startLine: run[0], endLine: run[run.count - 1], depth: 0, kind: .comment)) }
            run = []
        }
        for l in lineComments.sorted() {
            if let last = run.last, l != last + 1 { flush() }
            run.append(l)
        }
        flush()
        return out.sorted { $0.startLine < $1.startLine }
    }
}
