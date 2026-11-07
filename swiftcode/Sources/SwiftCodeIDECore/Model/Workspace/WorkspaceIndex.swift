import Foundation

public enum WorkspaceSearch {
    public struct Match: Equatable, Sendable {
        public var line: Int
        public var text: String
        public var range: NSRange
        public var column = 1
        public var highlight = NSRange(location: 0, length: 0)
        public var lineSpan = 1
        public var matchedText = ""
        public init(line: Int, text: String, range: NSRange, column: Int = 1, highlight: NSRange = NSRange(location: 0, length: 0),
                    lineSpan: Int = 1, matchedText: String = "") {
            self.line = line
            self.text = text
            self.range = range
            self.column = column
            self.highlight = highlight
            self.lineSpan = lineSpan
            self.matchedText = matchedText
        }
    }

    public struct Options: Equatable, Sendable {
        public var regularExpression = false
        public var wholeWord = false
        public var ignoreCase = true
        public enum Anchor: Sendable { case none, start, end }
        public var anchor: Anchor = .none
        public init(regularExpression: Bool = false, wholeWord: Bool = false, ignoreCase: Bool = true, anchor: Anchor = .none) {
            self.regularExpression = regularExpression
            self.wholeWord = wholeWord
            self.ignoreCase = ignoreCase
            self.anchor = anchor
        }

        package func expression(for query: String) -> NSRegularExpression? {
            let q = FindQuery(query, options: self)
            return FindQuery.expression(regularExpression ? query : NSRegularExpression.escapedPattern(for: query), match: q.match, ignoreCase: ignoreCase)
        }
    }

    public struct FileResult: Equatable, Sendable {
        public var path: String
        public var matches: [Match]
    }

    public static func search(_ query: String, in root: NavigatorNode, options: Options = Options(), limit: Int = 1000) -> [FileResult] {
        let q = FindQuery(query, options: options)
        let files = FindScopeResolver(root: root).candidates(for: .workspace)
        return FindEngine.search(FindEngine.Request(query: q, files: files, limit: limit)).files
    }

    public static func search(_ query: String, inText text: String, options: Options = Options()) -> [Match] {
        guard !query.isEmpty, let regex = options.expression(for: query) else { return [] }
        return search(regex, inText: text)
    }

    package static func search(_ regex: NSRegularExpression, inText text: String) -> [Match] {
        FindMatcher(regexes: [regex], allWords: false, needles: [], ignoreCase: false).matches(in: text)
    }
}

public enum SymbolScanner {
    public struct Symbol: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case `class`, `struct`, `enum`, `protocol`, `extension`, actor, function, `typealias`, macro, interface, implementation
            case property, enumCase, initializer
            var isContainer: Bool { [.class, .struct, .enum, .protocol, .extension, .actor].contains(self) }
        }
        public var kind: Kind
        public var name: String
        public var line: Int
        public var children: [Symbol] = []
        public init(kind: Kind, name: String, line: Int, children: [Symbol] = []) {
            self.kind = kind
            self.name = name
            self.line = line
            self.children = children
        }
    }

    public static func symbols(in text: String, language: SourceTokenizer.Language) -> [Symbol] {
        guard language.isCode else { return [] }
        var units = Array(text.utf16)
        for t in SourceTokenizer(language: language).tokens(in: text)
        where [.comment, .docComment, .string, .preprocessor].contains(t.kind) {
            for i in t.range.location..<min(NSMaxRange(t.range), units.count) where units[i] != 10 { units[i] = 32 }
        }
        let clean = String(decoding: units, as: UTF16.self)
        let index = LineIndex(clean)
        let words = scanWords(clean)
        var out: [Symbol] = []
        let swiftKinds: [String: Symbol.Kind] = [
            "class": .class, "struct": .struct, "enum": .enum, "protocol": .protocol, "extension": .extension,
            "actor": .actor, "func": .function, "typealias": .typealias, "macro": .macro,
        ]
        if language == .swift { return swiftSymbols(words, index: index, kinds: swiftKinds) }
        for (i, w) in words.enumerated() where w.depth == 0 {
            do {
                if w.text == "@interface" || w.text == "@implementation", i + 1 < words.count {
                    out.append(Symbol(kind: w.text == "@interface" ? .interface : .implementation, name: words[i + 1].text,
                                      line: index.line(at: w.offset)))
                } else if w.text == "struct" || w.text == "enum", i + 2 < words.count, words[i + 1].isIdentifier, words[i + 2].text == "{" {
                    out.append(Symbol(kind: w.text == "struct" ? .struct : .enum, name: words[i + 1].text, line: index.line(at: w.offset)))
                } else if w.isIdentifier, i + 1 < words.count, words[i + 1].text == "(",
                          let close = words[(i + 1)...].firstIndex(where: { $0.text == ")" && $0.depth == 0 }),
                          close + 1 < words.count, words[close + 1].text == "{",
                          !["if", "while", "for", "switch", "return", "sizeof"].contains(w.text) {
                    out.append(Symbol(kind: .function, name: w.text, line: index.line(at: w.offset)))
                }
            }
        }
        return out
    }

    static func swiftSymbols(_ words: [Word], index: LineIndex, kinds: [String: Symbol.Kind]) -> [Symbol] {
        var stack: [(Symbol, Int)] = []
        var top: [Symbol] = []
        var pending: (Symbol, Int)?
        func add(_ s: Symbol) {
            if stack.isEmpty { top.append(s) } else { stack[stack.count - 1].0.children.append(s) }
        }
        func close() {
            let (s, _) = stack.removeLast()
            add(s)
        }
        for (i, w) in words.enumerated() {
            if w.text == "}" {
                while let last = stack.last, w.depth < last.1 { _ = last; close() }
                continue
            }
            if w.text == "{" {
                if let (s, d) = pending, w.depth == d { stack.append((s, d + 1)); pending = nil }
                continue
            }
            let memberDepth = stack.last?.1 ?? 0
            guard w.depth == memberDepth, pending == nil else { continue }
            let next = i + 1 < words.count ? words[i + 1] : nil
            let line = index.line(at: w.offset)
            if let kind = kinds[w.text], let n = next, n.isIdentifier, !(w.text == "class" && (n.text == "func" || n.text == "var")) {
                let s = Symbol(kind: kind, name: n.text, line: line)
                if kind.isContainer { pending = (s, w.depth) } else { add(s) }
            } else if !stack.isEmpty, ["var", "let"].contains(w.text), let n = next, n.isIdentifier {
                add(Symbol(kind: .property, name: n.text, line: line))
            } else if !stack.isEmpty, w.text == "case", stack.last?.0.kind == .enum, let n = next, n.isIdentifier {
                add(Symbol(kind: .enumCase, name: n.text, line: line))
            } else if !stack.isEmpty, w.text == "init" {
                add(Symbol(kind: .initializer, name: "init", line: line))
            }
        }
        if let (s, _) = pending { add(s) }
        while !stack.isEmpty { close() }
        return top
    }

    struct Word { var text: String; var offset: Int; var depth: Int; var isIdentifier: Bool }

    static func scanWords(_ s: String) -> [Word] {
        let u = Array(s.utf16)
        var out: [Word] = []
        var depth = 0
        var i = 0
        func isStart(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127 }
        func isPart(_ c: UInt16) -> Bool { isStart(c) || (c >= 48 && c <= 57) }
        while i < u.count {
            let c = u[i]
            if isStart(c) || (c == 64 && i + 1 < u.count && isStart(u[i + 1])) {
                let start = i
                i += 1
                while i < u.count && isPart(u[i]) { i += 1 }
                let text = String(decoding: u[start..<i], as: UTF16.self)
                out.append(Word(text: text, offset: start, depth: depth, isIdentifier: c != 64))
                continue
            }
            switch c {
            case 123: out.append(Word(text: "{", offset: i, depth: depth, isIdentifier: false)); depth += 1
            case 125: depth = max(0, depth - 1); out.append(Word(text: "}", offset: i, depth: depth, isIdentifier: false))
            case 40: out.append(Word(text: "(", offset: i, depth: depth, isIdentifier: false))
            case 41: out.append(Word(text: ")", offset: i, depth: depth, isIdentifier: false))
            case 59: out.append(Word(text: ";", offset: i, depth: depth, isIdentifier: false))
            default: break
            }
            i += 1
        }
        return out
    }
}

public struct BuildReport: Equatable, Sendable {
    public var title: String
    public var date: Date
    public var succeeded: Bool
    public var log: [String]
    public var errorCount: Int
    public var warningCount: Int
    public var context = ReportContext()
    package init(title: String, date: Date, succeeded: Bool, log: [String], errorCount: Int, warningCount: Int, context: ReportContext = ReportContext()) {
        self.title = title
        self.date = date
        self.succeeded = succeeded
        self.log = log
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.context = context
    }
}
