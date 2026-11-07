import Foundation

public struct IndentOptions: Equatable, Sendable {
    public var usesTabs: Bool
    public var tabWidth: Int
    public var indentWidth: Int

    public init(usesTabs: Bool = false, tabWidth: Int = 4, indentWidth: Int = 4) {
        self.usesTabs = usesTabs
        self.tabWidth = max(1, tabWidth)
        self.indentWidth = max(1, indentWidth)
    }

    public init(unit: String, tabWidth: Int = 4) {
        if unit.contains("\t") { self.init(usesTabs: true, tabWidth: tabWidth, indentWidth: tabWidth) }
        else { self.init(usesTabs: false, tabWidth: tabWidth, indentWidth: max(1, unit.count)) }
    }

    public var unit: String { usesTabs && indentWidth == tabWidth ? "\t" : string(forColumn: indentWidth) }

    public func column(of whitespace: some StringProtocol) -> Int {
        var c = 0
        for ch in whitespace { c = ch == "\t" ? (c / tabWidth + 1) * tabWidth : c + 1 }
        return c
    }

    public func string(forColumn column: Int) -> String {
        let c = max(0, column)
        if usesTabs { return String(repeating: "\t", count: c / tabWidth) + String(repeating: " ", count: c % tabWidth) }
        return String(repeating: " ", count: c)
    }
}

extension SyntaxDocument {
    public var indentsByStructure: Bool {
        switch language {
        case .swift, .objc, .c, .cpp, .metal, .json, .xml, .shell, .xcconfig: true
        case .markdown, .yaml, .plain: false
        }
    }

    static let labelWords: Set<String> = ["case", "default"]

    static func words(_ s: Substring) -> [Substring] {
        s.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "#" || $0 == "@") })
    }

    func opensSwitch(_ event: BlockEvent, line n: Int) -> Bool {
        guard event.kind == .bracket(123) else { return false }
        let r = lineRange(n)
        let before = String(decoding: units[r.lowerBound..<event.offset], as: UTF16.self)
        if Self.words(Substring(before)).contains("switch") { return true }
        if before.allSatisfy({ $0 == " " || $0 == "\t" }), n > 0 { return Self.words(Substring(lineText(n - 1))).contains("switch") }
        return false
    }

    public func computedIndent(forLine n: Int, options: IndentOptions, indents: [Int: String] = [:], blankLines: Bool = false) -> String? {
        guard indentsByStructure else { return nil }
        let start = startState(ofLine: n)
        if let open = start.open, open.isCommentOrString || open == .preprocessor || open == .codeSpan { return nil }
        if language == .xml, start.mode != 0 { return nil }
        let r = lineRange(n)
        let text = String(decoding: units[r], as: UTF16.self)
        let body = text.drop { $0 == " " || $0 == "\t" }
        if body.isEmpty && !blankLines { return "" }
        if language.isCFamily, body.hasPrefix("#") { return "" }
        let first = r.lowerBound + (text.utf16.count - body.utf16.count)
        guard let (opener, openerLine) = enclosingOpener(before: first) else { return continuation(body, base: 0, options) }
        let openerIndent = indents[openerLine] ?? leadingWhitespace(openerLine)
        let base = options.column(of: openerIndent)
        if let e = blockEvents(onLine: n).first, !e.isOpen, e.offset == first { return options.string(forColumn: base) }
        if startsWithClosingKeyword(body) || (language == .xml && body.hasPrefix("</")) { return options.string(forColumn: base) }
        if language == .swift || language.isCFamily, let w = Self.words(body.prefix(24)).first,
           Self.labelWords.contains(String(w)) || (w == "@unknown" && body.contains("default")), opensSwitch(opener, line: openerLine) {
            return options.string(forColumn: base)
        }
        return continuation(body, base: base + options.indentWidth, options)
    }

    func startsWithClosingKeyword(_ body: Substring) -> Bool {
        guard language == .shell, let w = Self.words(body.prefix(8)).first else { return false }
        return ["fi", "done", "esac", "else", "elif"].contains(String(w)) && (body.count == w.count || !(body.dropFirst(w.count).first?.isLetter ?? false))
    }

    func continuation(_ body: Substring, base: Int, _ options: IndentOptions) -> String {
        if language == .swift, body.hasPrefix("."), let c = body.dropFirst().first, c.isLetter || c == "_" {
            return options.string(forColumn: base + options.indentWidth)
        }
        return options.string(forColumn: base)
    }

    public func reindent(lines: ClosedRange<Int>, options: IndentOptions, selection: NSRange) -> TypingEdit? {
        var indents: [Int: String] = [:]
        var newLines: [String] = []
        var changed = false
        for n in lines {
            let old = lineText(n)
            let ws = leadingWhitespace(n)
            guard let indent = computedIndent(forLine: n, options: options, indents: indents) else {
                newLines.append(old)
                continue
            }
            indents[n] = indent
            let new = indent + old.dropFirst(ws.count)
            if new != old { changed = true }
            newLines.append(String(new))
        }
        guard changed else { return nil }
        let a = lineStart(lines.lowerBound), b = lineRange(lines.upperBound).upperBound
        let body = newLines.joined(separator: "\n")
        let sel: NSRange
        if selection.length == 0 {
            let caretLine = line(containing: selection.location)
            var offset = a
            for (k, n) in lines.enumerated() {
                if n == caretLine {
                    let oldWS = (leadingWhitespace(n) as NSString).length
                    let newWS = ((indents[n] ?? leadingWhitespace(n)) as NSString).length
                    let col = selection.location - lineStart(n)
                    let newCol = col <= oldWS ? newWS : col - oldWS + newWS
                    sel = NSRange(location: offset + min(newCol, (newLines[k] as NSString).length), length: 0)
                    return TypingEdit(range: NSRange(location: a, length: b - a), replacement: body, selection: sel)
                }
                offset += (newLines[k] as NSString).length + 1
            }
            sel = NSRange(location: a, length: 0)
        } else {
            sel = NSRange(location: a, length: (body as NSString).length)
        }
        return TypingEdit(range: NSRange(location: a, length: b - a), replacement: body, selection: sel)
    }
}
