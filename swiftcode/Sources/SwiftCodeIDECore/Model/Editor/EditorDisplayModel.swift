import Foundation

public enum EditorDisplayModel {
    static func lines(_ text: String) -> [Substring] { text.split(separator: "\n", omittingEmptySubsequences: false) }

    public static func markSeparatorLines(in text: String) -> [Int] {
        var out: [Int] = []
        for (i, l) in lines(text).enumerated() {
            let t = l.drop { $0 == " " || $0 == "\t" }
            if t.hasPrefix("// MARK: -") || t.hasPrefix("//MARK: -") { out.append(i + 1) }
        }
        return out
    }

    public struct Conditional: Equatable, Sendable {
        public struct Branch: Equatable, Sendable {
            public var line: Int
            public var condition: String?
        }
        public var branches: [Branch]
        public var endifLine: Int
    }

    static func directive(_ line: Substring) -> (keyword: String, rest: String)? {
        var t = line.drop { $0 == " " || $0 == "\t" }
        guard t.first == "#" else { return nil }
        t = t.dropFirst().drop { $0 == " " || $0 == "\t" }
        let keyword = String(t.prefix { $0.isLetter })
        guard ["if", "ifdef", "ifndef", "elseif", "elif", "else", "endif"].contains(keyword) else { return nil }
        var rest = String(t.dropFirst(keyword.count))
        if let r = rest.range(of: "//") { rest = String(rest[..<r.lowerBound]) }
        if let r = rest.range(of: "/*") { rest = String(rest[..<r.lowerBound]) }
        return (keyword, rest.trimmingCharacters(in: .whitespaces))
    }

    public static func conditionals(in text: String) -> [Conditional] {
        var open: [[Conditional.Branch]] = []
        var out: [Conditional] = []
        for (i, l) in lines(text).enumerated() {
            guard let (k, rest) = directive(l) else { continue }
            switch k {
            case "if": open.append([.init(line: i + 1, condition: rest)])
            case "ifdef": open.append([.init(line: i + 1, condition: "defined(\(rest))")])
            case "ifndef": open.append([.init(line: i + 1, condition: "!defined(\(rest))")])
            case "elseif", "elif": if !open.isEmpty { open[open.count - 1].append(.init(line: i + 1, condition: rest)) }
            case "else": if !open.isEmpty { open[open.count - 1].append(.init(line: i + 1, condition: nil)) }
            default: if let b = open.popLast() { out.append(Conditional(branches: b, endifLine: i + 1)) }
            }
        }
        return out
    }

    public static func endifConditions(in text: String) -> [Int: String] {
        var out: [Int: String] = [:]
        for c in conditionals(in: text) { if let cond = c.branches.first?.condition, !cond.isEmpty { out[c.endifLine] = cond } }
        return out
    }

    public static func inactiveLines(in text: String, defined: Set<String>? = nil) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        for c in conditionals(in: text) {
            var earlierTrue = false, earlierUnknown = false
            for (i, b) in c.branches.enumerated() {
                let value: Bool? = b.condition.map { evaluate($0, defined: defined) } ?? (earlierTrue ? false : (earlierUnknown ? nil : true))
                let inactive = earlierTrue || value == false
                let end = i + 1 < c.branches.count ? c.branches[i + 1].line : c.endifLine
                if inactive, end - 1 >= b.line + 1 { out.append((b.line + 1)...(end - 1)) }
                if value == true { earlierTrue = true }
                if value == nil { earlierUnknown = true }
            }
        }
        return out.sorted { $0.lowerBound < $1.lowerBound }
    }

    public static func evaluate(_ condition: String, defined: Set<String>?) -> Bool? {
        var p = ConditionParser(Array(condition), defined: defined)
        guard let v = p.parseOr(), p.atEnd else { return nil }
        return v.value
    }

    struct Value { var value: Bool? }

    struct ConditionParser {
        var chars: [Character]
        var i = 0
        let defined: Set<String>?
        init(_ c: [Character], defined: Set<String>?) { chars = c; self.defined = defined }
        var atEnd: Bool { mutating get { skip(); return i >= chars.count } }
        mutating func skip() { while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 } }
        mutating func eat(_ s: String) -> Bool {
            skip()
            let a = Array(s)
            guard i + a.count <= chars.count, Array(chars[i..<i + a.count]) == a else { return false }
            i += a.count
            return true
        }
        mutating func parseOr() -> Value? {
            guard var l = parseAnd() else { return nil }
            while eat("||") {
                guard let r = parseAnd() else { return nil }
                l = Value(value: l.value == true || r.value == true ? true : (l.value == false && r.value == false ? false : nil))
            }
            return l
        }
        mutating func parseAnd() -> Value? {
            guard var l = parseUnary() else { return nil }
            while eat("&&") {
                guard let r = parseUnary() else { return nil }
                l = Value(value: l.value == false || r.value == false ? false : (l.value == true && r.value == true ? true : nil))
            }
            return l
        }
        mutating func parseUnary() -> Value? {
            if eat("!") { return parseUnary().map { Value(value: $0.value.map(!)) } }
            if eat("(") {
                guard let v = parseOr(), eat(")") else { return nil }
                return v
            }
            skip()
            let start = i
            while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { i += 1 }
            guard i > start else { return nil }
            let word = String(chars[start..<i])
            if let n = Int(word) { return Value(value: n != 0) }
            if word == "true" { return Value(value: true) }
            if word == "false" { return Value(value: false) }
            if eat("(") {
                let argStart = i
                var depth = 1
                while i < chars.count, depth > 0 {
                    if chars[i] == "(" { depth += 1 } else if chars[i] == ")" { depth -= 1 }
                    i += 1
                }
                guard depth == 0 else { return nil }
                let arg = String(chars[argStart..<(i - 1)]).trimmingCharacters(in: .whitespaces)
                if word == "defined" { return Value(value: defined.map { $0.contains(arg) }) }
                return Value(value: nil)
            }
            return Value(value: defined.map { $0.contains(word) })
        }
    }

    public static func commentDelimiters(_ tokens: [SourceTokenizer.Token], in text: NSString) -> (doc: [NSRange], plain: [NSRange]) {
        var doc: [NSRange] = [], plain: [NSRange] = []
        for t in tokens where t.kind == .comment || t.kind == .docComment {
            guard NSMaxRange(t.range) <= text.length, t.range.length >= 2 else { continue }
            let s = text.substring(with: t.range)
            var r: [NSRange] = []
            if s.hasPrefix("///") { r.append(NSRange(location: t.range.location, length: 3)) }
            else if s.hasPrefix("//") { r.append(NSRange(location: t.range.location, length: 2)) }
            else if s.hasPrefix("/*") {
                r.append(NSRange(location: t.range.location, length: s.hasPrefix("/**") && t.kind == .docComment ? 3 : 2))
                if s.hasSuffix("*/"), t.range.length >= 4 { r.append(NSRange(location: NSMaxRange(t.range) - 2, length: 2)) }
            }
            if t.kind == .docComment { doc += r } else { plain += r }
        }
        return (doc, plain)
    }

    static let declarationPattern = try! NSRegularExpression(
        pattern: #"\b(class|struct|enum|extension|protocol|actor|func|init|deinit|subscript|var|@interface|@implementation|@protocol)\b"#)

    public static func structureHeaderLines(_ regions: [FoldRegion], topLine: Int, limit: Int = 3, lineText: (Int) -> String) -> [Int] {
        let enclosing = regions.filter { $0.startLine < topLine && $0.endLine >= topLine }
            .filter { r in
                let t = lineText(r.startLine)
                return declarationPattern.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil
            }
            .sorted { $0.depth < $1.depth }
            .map(\.startLine)
        return Array(enclosing.suffix(limit))
    }
}
