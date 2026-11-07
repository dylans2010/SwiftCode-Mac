struct JSONLexer: LineLexer {
    func lex(_ l: LineText, state: inout LexState, into out: inout [SyntaxToken]) {
        var i = l.start
        if state.mode == 1 {
            guard let e = l.find("*/", from: i) else { out.add(.comment, l.start, l.end); return }
            out.add(.comment, l.start, e + 2)
            i = e + 2
            state = .initial
        }
        while i < l.end {
            let c = l[i]
            let s = i
            if c == 47, l[i + 1] == 47 { out.add(.comment, s, l.end); return }
            if c == 47, l[i + 1] == 42 {
                guard let e = l.find("*/", from: i + 2) else {
                    out.add(.comment, s, l.end)
                    state = LexState(open: .comment, mode: 1)
                    return
                }
                i = e + 2
                out.add(.comment, s, i)
                continue
            }
            if c == 34 {
                i += 1
                while i < l.end, l[i] != 34 { i += l[i] == 92 ? 2 : 1 }
                i = min(i + 1, l.end)
                let next = l.firstNonSpace(from: i)
                out.add(l[next] == 58 ? .key : .string, s, i)
                continue
            }
            if isDigit(c) || (c == 45 && isDigit(l[i + 1])) {
                i = numberEnd(l, c == 45 ? i + 1 : i)
                out.add(.number, s, i)
                continue
            }
            if isIdentStart(c) {
                while i < l.end, isIdentPart(l[i]) { i += 1 }
                let w = l.string(s, i)
                if w == "true" || w == "false" || w == "null" { out.add(.keyword, s, i) }
                continue
            }
            i += 1
        }
    }
}

struct YAMLLexer: LineLexer {
    static let constants: Set<String> = ["true", "false", "True", "False", "TRUE", "FALSE", "yes", "no", "Yes", "No", "on", "off",
                                         "null", "Null", "NULL", "~"]

    enum Mode: UInt8 { case plain = 0, blockScalar = 1, singleQuoted = 2, doubleQuoted = 3 }

    func lex(_ l: LineText, state: inout LexState, into out: inout [SyntaxToken]) {
        var i = l.start
        let indent = l.firstNonSpace(from: l.start) - l.start
        switch Mode(rawValue: state.mode) ?? .plain {
        case .blockScalar:
            if l.isBlank || indent > Int(state.aux) {
                out.add(.string, l.start, l.end)
                state.open = l.isBlank ? nil : .string
                return
            }
            state = .initial
        case .singleQuoted, .doubleQuoted:
            let q: UInt16 = state.mode == Mode.singleQuoted.rawValue ? 39 : 34
            let (e, closed) = quoted(l, from: i, quote: q)
            out.add(.string, l.start, e)
            if !closed { return }
            state = .initial
            i = e
        case .plain:
            break
        }
        if i == l.start {
            if l.matches("---", at: i) && (l[i + 3] == 0 || isSpace(l[i + 3])) || l.matches("...", at: i) && (l[i + 3] == 0 || isSpace(l[i + 3])) {
                out.add(.preprocessor, i, i + 3)
                i += 3
            } else if l[i] == 37 {
                out.add(.preprocessor, i, l.end)
                return
            }
        }
        var atValueStart = true
        while i < l.end {
            let c = l[i]
            let s = i
            if isSpace(c) { i += 1; continue }
            if c == 35, s == l.start || isSpace(l[s - 1]) { out.add(.comment, s, l.end); return }
            if c == 45, isSpace(l[i + 1]) || i + 1 == l.end, atValueStart {
                out.add(.listMarker, s, i + 1)
                i += 1
                continue
            }
            if c == 39 || c == 34 {
                let (e, closed) = quoted(l, from: i + 1, quote: c)
                let next = l.firstNonSpace(from: e)
                out.add(atValueStart && l[next] == 58 ? .key : .string, s, e)
                if !closed {
                    state = LexState(open: .string, mode: c == 39 ? Mode.singleQuoted.rawValue : Mode.doubleQuoted.rawValue)
                    return
                }
                i = e
                continue
            }
            if c == 38 || c == 42 {
                i += 1
                while i < l.end, !isSpace(l[i]), l[i] != 44, l[i] != 93, l[i] != 125 { i += 1 }
                out.add(.variable, s, i)
                continue
            }
            if c == 33 {
                while i < l.end, !isSpace(l[i]) { i += 1 }
                out.add(.preprocessor, s, i)
                continue
            }
            if c == 124 || c == 62, isBlockScalarHeader(l, i) {
                out.add(.keyword, s, l.end)
                state = LexState(mode: Mode.blockScalar.rawValue, aux: Int32(indent))
                return
            }
            if c == 123 || c == 125 || c == 91 || c == 93 || c == 44 || c == 58 {
                atValueStart = c != 58
                i += 1
                continue
            }
            var j = i
            while j < l.end {
                let d = l[j]
                if d == 58, isSpace(l[j + 1]) || j + 1 == l.end { break }
                if d == 35, isSpace(l[j - 1]) { break }
                if d == 44 || d == 93 || d == 125, j > i { break }
                j += 1
            }
            var e = j
            while e > i, isSpace(l[e - 1]) { e -= 1 }
            if l[j] == 58, atValueStart {
                out.add(.key, s, e)
            } else if l.word(s, e, in: Self.constants) {
                out.add(.keyword, s, e)
            } else if isDigit(c) || ((c == 45 || c == 43 || c == 46) && isDigit(l[i + 1])) {
                if numberEnd(l, c == 45 || c == 43 ? i + 1 : i) == e { out.add(.number, s, e) }
            }
            atValueStart = false
            i = max(j, i + 1)
        }
    }

    func isBlockScalarHeader(_ l: LineText, _ i: Int) -> Bool {
        var j = i + 1
        while j < l.end, l[j] == 43 || l[j] == 45 || isDigit(l[j]) { j += 1 }
        let k = l.firstNonSpace(from: j)
        return k == l.end || (l[k] == 35 && k > j)
    }

    func quoted(_ l: LineText, from i: Int, quote: UInt16) -> (Int, Bool) {
        var j = i
        while j < l.end {
            if quote == 34, l[j] == 92 { j += 2; continue }
            if l[j] == quote {
                if quote == 39, l[j + 1] == 39 { j += 2; continue }
                return (j + 1, true)
            }
            j += 1
        }
        return (l.end, false)
    }
}

struct XcconfigLexer: LineLexer {
    func lex(_ l: LineText, state: inout LexState, into out: inout [SyntaxToken]) {
        var i = l.firstNonSpace(from: l.start)
        if l[i] == 35 {
            var j = i + 1
            while j < l.end, isIdentPart(l[j]) || l[j] == 63 { j += 1 }
            out.add(.preprocessor, i, j)
            i = j
        } else if isIdentStart(l[i]) {
            var j = i
            while j < l.end, isIdentPart(l[j]) { j += 1 }
            out.add(.key, i, j)
            i = j
            while l[i] == 91 {
                var k = i
                while k < l.end, l[k] != 93 { k += 1 }
                k = min(k + 1, l.end)
                out.add(.attribute, i, k)
                i = k
            }
        }
        while i < l.end {
            let c = l[i]
            let s = i
            if c == 47, l[i + 1] == 47 { out.add(.comment, s, l.end); return }
            if c == 34 {
                i += 1
                while i < l.end, l[i] != 34 { i += l[i] == 92 ? 2 : 1 }
                i = min(i + 1, l.end)
                out.add(.string, s, i)
                continue
            }
            if c == 36 {
                let close: UInt16? = l[i + 1] == 40 ? 41 : (l[i + 1] == 123 ? 125 : nil)
                if let close {
                    var j = i + 2
                    var depth = 1
                    while j < l.end {
                        if l[j] == l[i + 1] { depth += 1 } else if l[j] == close { depth -= 1; if depth == 0 { break } }
                        j += 1
                    }
                    i = min(j + 1, l.end)
                } else {
                    i += 1
                    while i < l.end, isIdentPart(l[i]) { i += 1 }
                }
                out.add(.variable, s, i)
                continue
            }
            if !isSpace(c) {
                while i < l.end, !isSpace(l[i]), l[i] != 36, l[i] != 34, !(l[i] == 47 && l[i + 1] == 47) { i += 1 }
                let w = l.string(s, i)
                if w == "YES" || w == "NO" { out.add(.keyword, s, i) }
                else if isDigit(c), numberEnd(l, s) == i { out.add(.number, s, i) }
                continue
            }
            i += 1
        }
    }
}
