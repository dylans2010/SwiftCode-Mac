import Foundation

// MARK: - SDKKeywordHighlighter
//
// A real, dependency-free implementation of `SDKSyntaxHighlighter` for the
// Studio code editor. Handles `.swift` and `.typescript`/`.javascript`
// with dedicated scanners, plus cheap correct scanners for `.json` and
// `.markdown`; `.plaintext` is a single plain run.
//
// ## Approach (why it cannot blow up)
//
// Every language is scanned in ONE linear pass over the input's UTF-16
// code units (`Array(text.utf16)`), so emitted `Range<Int>` values are
// already UTF-16 offsets and apply directly to `NSAttributedString`.
//
// * No regular expressions anywhere: every construct is recognized by a
//   hand-written state machine, so there are no catastrophic-backtracking
//   inputs.
// * The scan index only ever moves forward. Nested constructs (Swift
//   `/* /* */ */` comments, string interpolation `\("...")`, template
//   literal `` `${`...`}` ``) are handled with an explicit heap-allocated
//   stack, never recursion, so adversarial nesting cannot overflow the
//   call stack.
// * Each UTF-16 unit is examined a constant number of times, giving O(n)
//   time and O(n) memory (the unit array, two per-unit classification
//   bitmaps, and the token list).
// * Identifier classification (what counts as a letter/digit, including
//   non-ASCII scalars) is precomputed once per call into per-unit bitmaps,
//   so the hot loop only does array lookups.
//
// ## Token guarantees
//
// Scanners emit only "interesting" tokens (keyword/string/comment/number/
// typeName) in strictly increasing offset order. `highlight` then fills
// the gaps with `.plain`, so the returned array is sorted, non-overlapping,
// and covers `0..<text.utf16.count`.
//
// ## Known simplifications (deliberate)
//
// * TypeScript regex literals are detected with the standard
//   previous-significant-token heuristic (`/re/` after `=`, `(`, `,`,
//   `return`, … is a regex; after an identifier, `)`, `]`, or a quote it
//   is division). Pathological cases can mis-highlight one run; they can
//   never corrupt offsets.
// * Markdown highlighting is intentionally shallow: headings, fenced and
//   inline code, list markers, link destinations, and HTML comments.
// * A leading-dot float (`.5`) is recognized in TypeScript only; Swift
//   does not allow `.5` as a literal (it parses as member access).

public struct SDKKeywordHighlighter: SDKSyntaxHighlighter, Sendable {
    public init() {}

    public func highlight(_ text: String, language: SDKCodeLanguage) -> [SDKToken] {
        let units = Array(text.utf16)
        let n = units.count
        guard n > 0 else { return [] }

        let classifier = _SDKIdentifierClassifier(text: text)
        let body: [SDKToken]
        switch language {
        case .swift:
            body = _sdkScanSwift(units: units, classifier: classifier)
        case .typescript, .javascript:
            body = _sdkScanTypeScript(units: units, classifier: classifier)
        case .json:
            body = _sdkScanJSON(units: units, classifier: classifier)
        case .markdown:
            body = _sdkScanMarkdown(units: units)
        case .plaintext:
            body = []
        }

        // Fill gaps with `.plain`. Scanners append in increasing offset
        // order and never overlap, so a single forward sweep suffices.
        var out: [SDKToken] = []
        out.reserveCapacity(body.count + 1)
        var cursor = 0
        for token in body {
            let lo = token.range.lowerBound
            if lo > cursor {
                out.append(SDKToken(range: cursor..<lo, kind: .plain))
            }
            if token.range.upperBound > cursor {
                out.append(token)
                cursor = token.range.upperBound
            }
        }
        if cursor < n {
            out.append(SDKToken(range: cursor..<n, kind: .plain))
        }
        return out
    }
}

// MARK: - Identifier classification

/// Precomputed per-UTF-16-unit identifier flags for one `highlight` call.
/// Both units of a surrogate pair share their scalar's flags, so token
/// ranges never split a Unicode scalar in half.
private struct _SDKIdentifierClassifier {
    let isStart: [Bool]
    let isContinue: [Bool]

    init(text: String) {
        let n = text.utf16.count
        var s = [Bool](repeating: false, count: n)
        var c = [Bool](repeating: false, count: n)
        var u = 0
        for scalar in text.unicodeScalars {
            let start: Bool = {
                // `_` and `$` are identifier characters in Swift and
                // TypeScript (`$0`, `$el`); neither is alphabetic.
                if scalar.value == 0x5F || scalar.value == 0x24 { return true }
                return scalar.properties.isAlphabetic
            }()
            let cont = start || scalar.properties.numericType != nil
            let w = scalar.utf16.count
            for k in 0..<w {
                s[u + k] = start
                c[u + k] = cont
            }
            u += w
        }
        self.isStart = s
        self.isContinue = c
    }
}

// MARK: - Shared primitives

/// ASCII letters, digits, or `_`: the tail of a numeric literal such as
/// `0xFF`, `0b101`, `1_000`, or `1e10`.
private func _sdkIsNumberChar(_ c: UInt16) -> Bool {
    (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
}

/// Scans a numeric literal starting at a digit. Consumes alphanumerics and
/// `_` (hex/octal/binary digits, exponents, separators) plus a `.` only
/// when directly followed by a digit, so `1...5` and `a.b` are not glued
/// into one number.
private func _sdkScanNumber(_ units: [UInt16], from start: Int) -> Int {
    var i = start
    let n = units.count
    while i < n {
        let c = units[i]
        if _sdkIsNumberChar(c) {
            i += 1
            continue
        }
        if c == 0x2E /* . */, i + 1 < n, units[i + 1] >= 0x30, units[i + 1] <= 0x39 {
            i += 1 // consume the '.'; the digit is consumed next iteration
            continue
        }
        break
    }
    return i
}

/// Nested `/* /* */ */` block comment starting after the opening `/*`.
/// Swift nests block comments; the TypeScript scanner uses its own
/// non-nesting variant.
private func _sdkScanNestedBlockComment(_ units: [UInt16], from start: Int) -> Int {
    var i = start
    var depth = 1
    let n = units.count
    while i < n, depth > 0 {
        if units[i] == 0x2F /* / */, i + 1 < n, units[i + 1] == 0x2A /* * */ {
            depth += 1
            i += 2
        } else if units[i] == 0x2A /* * */, i + 1 < n, units[i + 1] == 0x2F /* / */ {
            depth -= 1
            i += 2
        } else {
            i += 1
        }
    }
    return i
}

/// Number of consecutive `#` units starting at `i` (0 when `units[i]`
/// is not `#`).
private func _sdkHashRun(_ units: [UInt16], at i: Int) -> Int {
    var j = i
    var h = 0
    while j < units.count, units[j] == 0x23 /* # */ {
        h += 1
        j += 1
    }
    return h
}

/// True when `i` starts a string opener: `"`, `"""`, `#"..."#`, `#"""…"""#`.
private func _sdkIsStringOpener(_ units: [UInt16], at i: Int) -> Bool {
    let j = i + _sdkHashRun(units, at: i)
    return j < units.count && units[j] == 0x22 /* " */
}

/// True when the scalar starting at UTF-16 offset `i` is uppercase.
/// Used for the "Capitalized identifier ⇒ type name" heuristic.
private func _sdkStartsWithUppercase(_ units: [UInt16], at i: Int) -> Bool {
    let u = units[i]
    if u >= 0x41, u <= 0x5A { return true }
    if u <= 0x7F { return false }
    var v = UInt32(u)
    if u >= 0xD800, u <= 0xDBFF, i + 1 < units.count {
        let lo = units[i + 1]
        if lo >= 0xDC00, lo <= 0xDFFF {
            v = 0x10000 + ((UInt32(u) - 0xD800) << 10) + (UInt32(lo) - 0xDC00)
        }
    }
    guard let scalar = Unicode.Scalar(v) else { return false }
    return scalar.properties.isUppercase
}

// MARK: - Swift keyword table

private let _sdkSwiftKeywords: Set<String> = [
    // Declarations
    "associatedtype", "class", "deinit", "enum", "extension", "func",
    "import", "init", "inout", "let", "operator", "precedencegroup",
    "protocol", "struct", "subscript", "typealias", "var", "actor", "macro",
    // Statements
    "break", "case", "catch", "continue", "default", "defer", "do", "else",
    "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch",
    "throw", "where", "while",
    // Expressions and types
    "as", "any", "false", "is", "nil", "rethrows", "self", "Self", "super",
    "throws", "true", "try", "await", "async", "some",
    // Access levels and modifiers
    "private", "fileprivate", "internal", "public", "open", "package",
    "static", "final", "override", "mutating", "nonmutating", "lazy",
    "weak", "unowned", "required", "convenience", "dynamic", "indirect",
    "optional",
    // Common contextual keywords
    "get", "set", "willSet", "didSet",
]

// MARK: - Swift scanner

/// Frames for the explicit (non-recursive) Swift string scanner below.
private enum _SDKSwiftStringFrame {
    /// Inside a string literal; `rawHashes` is the `#` count of a raw
    /// string (`#"…"#`), 0 for ordinary strings.
    case string(triple: Bool, rawHashes: Int)
    /// Inside a `\(…)` (or `\#…(`) interpolation; tracks open parens.
    case interpolation(parenDepth: Int)
}

/// Scans one Swift string literal starting at `start` (a `"` or a raw
/// string opener like `#"`) and returns the offset one past its end.
///
/// Interpolation-aware at the token level: the whole literal — including
/// any `\(`…`)` regions, strings nested inside them, and comments —
/// becomes ONE `.string` token, so a `"` inside an interpolation never
/// terminates the outer literal early. Unterminated literals consume to
/// end of input rather than failing.
private func _sdkScanSwiftString(_ units: [UInt16], from start: Int) -> Int {
    let n = units.count
    var i = start
    let raw = _sdkHashRun(units, at: i)
    i += raw
    guard i < n, units[i] == 0x22 /* " */ else { return min(start + 1, n) }
    var triple = false
    if i + 2 < n, units[i + 1] == 0x22, units[i + 2] == 0x22 {
        triple = true
        i += 3
    } else {
        i += 1
    }

    var stack: [_SDKSwiftStringFrame] = [.string(triple: triple, rawHashes: raw)]
    while let frame = stack.last {
        if i >= n { break } // unterminated: consume to end of input
        switch frame {
        case .string(let isTriple, let rawHashes):
            let c = units[i]
            if c == 0x5C /* \ */ {
                if rawHashes == 0 {
                    if i + 1 < n, units[i + 1] == 0x28 /* ( */ {
                        // \( — interpolation begins
                        stack.append(.interpolation(parenDepth: 1))
                        i += 2
                    } else {
                        i = min(i + 2, n) // ordinary escape
                    }
                } else {
                    // Raw string: interpolation is \#…(
                    var j = i + 1
                    let h = _sdkHashRun(units, at: j)
                    j += h
                    if h == rawHashes, j < n, units[j] == 0x28 /* ( */ {
                        stack.append(.interpolation(parenDepth: 1))
                        i = j + 1
                    } else {
                        i += 1 // backslash is literal in raw strings
                    }
                }
                continue
            }
            if c == 0x22 /* " */ {
                if isTriple {
                    if i + 2 < n, units[i + 1] == 0x22, units[i + 2] == 0x22,
                       rawHashes == 0 || _sdkHashRun(units, at: i + 3) == rawHashes {
                        i += 3 + rawHashes
                        stack.removeLast()
                    } else {
                        i += 1
                    }
                } else if rawHashes == 0 || _sdkHashRun(units, at: i + 1) == rawHashes {
                    // A bare `"` always ends a non-raw string; a raw
                    // string needs its matching `#` count after it.
                    i += 1 + rawHashes
                    stack.removeLast()
                } else {
                    i += 1
                }
                continue
            }
            i += 1
        case .interpolation(let depth):
            let c = units[i]
            if c == 0x28 /* ( */ {
                stack[stack.count - 1] = .interpolation(parenDepth: depth + 1)
                i += 1
                continue
            }
            if c == 0x29 /* ) */ {
                if depth == 1 {
                    stack.removeLast()
                } else {
                    stack[stack.count - 1] = .interpolation(parenDepth: depth - 1)
                }
                i += 1
                continue
            }
            if (c == 0x22 /* " */ || c == 0x23 /* # */) && _sdkIsStringOpener(units, at: i) {
                // A string nested inside the interpolation, e.g. "\("a")".
                let r = _sdkHashRun(units, at: i)
                var j = i + r
                var t = false
                if j + 2 < n, units[j + 1] == 0x22, units[j + 2] == 0x22 {
                    t = true
                    j += 3
                } else {
                    j += 1
                }
                stack.append(.string(triple: t, rawHashes: r))
                i = j
                continue
            }
            if c == 0x2F /* / */, i + 1 < n {
                if units[i + 1] == 0x2F /* / */ {
                    i += 2
                    while i < n, units[i] != 0x0A /* \n */ { i += 1 }
                    continue
                }
                if units[i + 1] == 0x2A /* * */ {
                    i = _sdkScanNestedBlockComment(units, from: i + 2)
                    continue
                }
            }
            i += 1
        }
    }
    return i
}

private func _sdkScanSwift(units: [UInt16], classifier: _SDKIdentifierClassifier) -> [SDKToken] {
    var tokens: [SDKToken] = []
    var i = 0
    let n = units.count
    while i < n {
        let c = units[i]
        // Line comment
        if c == 0x2F /* / */, i + 1 < n, units[i + 1] == 0x2F {
            let start = i
            i += 2
            while i < n, units[i] != 0x0A /* \n */ { i += 1 }
            tokens.append(SDKToken(range: start..<i, kind: .comment))
            continue
        }
        // Block comment (nesting, per Swift)
        if c == 0x2F /* / */, i + 1 < n, units[i + 1] == 0x2A /* * */ {
            let start = i
            i = _sdkScanNestedBlockComment(units, from: i + 2)
            tokens.append(SDKToken(range: start..<i, kind: .comment))
            continue
        }
        // String literal (plain, triple-quoted, or raw)
        if c == 0x22 /* " */ || (c == 0x23 /* # */ && _sdkIsStringOpener(units, at: i)) {
            let start = i
            i = _sdkScanSwiftString(units, from: i)
            tokens.append(SDKToken(range: start..<i, kind: .string))
            continue
        }
        // `#` directive (#available, #if, #keyPath, …)
        if c == 0x23 /* # */ {
            let start = i
            i += 1
            if i < n, classifier.isStart[i] {
                while i < n, classifier.isContinue[i] { i += 1 }
                tokens.append(SDKToken(range: start..<i, kind: .keyword))
            }
            continue
        }
        // `@` attribute: @State → .typeName, @discardableResult → .keyword
        if c == 0x40 /* @ */ {
            let start = i
            i += 1
            if i < n, classifier.isStart[i] {
                let nameStart = i
                while i < n, classifier.isContinue[i] { i += 1 }
                let kind: SDKTokenKind =
                    _sdkStartsWithUppercase(units, at: nameStart) ? .typeName : .keyword
                tokens.append(SDKToken(range: start..<i, kind: kind))
            }
            continue
        }
        // Number
        if c >= 0x30, c <= 0x39 {
            let start = i
            i = _sdkScanNumber(units, from: i)
            tokens.append(SDKToken(range: start..<i, kind: .number))
            continue
        }
        // Identifier: keyword, Capitalized type name, or plain
        if classifier.isStart[i] {
            let start = i
            while i < n, classifier.isContinue[i] { i += 1 }
            let word = String(decoding: units[start..<i], as: UTF16.self)
            if _sdkSwiftKeywords.contains(word) {
                tokens.append(SDKToken(range: start..<i, kind: .keyword))
            } else if _sdkStartsWithUppercase(units, at: start) {
                tokens.append(SDKToken(range: start..<i, kind: .typeName))
            }
            continue
        }
        i += 1
    }
    return tokens
}

// MARK: - TypeScript keyword table

private let _sdkTypeScriptKeywords: Set<String> = [
    "break", "case", "catch", "class", "const", "continue", "debugger",
    "default", "delete", "do", "else", "enum", "export", "extends", "false",
    "finally", "for", "function", "if", "import", "in", "instanceof", "new",
    "null", "return", "super", "switch", "this", "throw", "true", "try",
    "typeof", "var", "void", "while", "with",
    // TypeScript-specific
    "interface", "type", "namespace", "declare", "abstract", "implements",
    "readonly", "private", "protected", "public", "static", "async", "await",
    "yield", "let", "of", "as", "from", "satisfies", "keyof", "infer",
    "never", "unknown", "any", "undefined", "is", "asserts", "out",
    "override", "using",
]

/// Keywords after which a `/` can still open a regex literal
/// (`return /re/`, `typeof /re/`, …). Any other identifier-like token
/// before `/` means division.
private let _sdkTSRegexAfterKeywords: Set<String> = [
    "return", "typeof", "instanceof", "in", "of", "new", "delete", "void",
    "throw", "case", "do", "else", "yield", "await",
]

/// Frames for the explicit (non-recursive) TypeScript string scanner.
private enum _SDKTSStringFrame {
    /// Inside a `'...'`, `"..."`, or `` `…` `` literal.
    case string(quote: UInt16)
    /// Inside a `${…}` template interpolation; tracks open braces.
    case interpolation(braceDepth: Int)
}

/// Scans one TypeScript string literal starting at `start` (a `'`, `"`,
/// or backtick) and returns the offset one past its end. Template
/// literals support `${…}` interpolation with arbitrary nesting; the
/// whole literal is ONE `.string` token. Unterminated literals consume to
/// end of input (single-line strings stop at a newline instead, so one
/// typo cannot swallow the rest of the file).
private func _sdkScanTSString(_ units: [UInt16], from start: Int) -> Int {
    let n = units.count
    var i = start + 1
    var stack: [_SDKTSStringFrame] = [.string(quote: units[start])]
    scan: while let frame = stack.last {
        if i >= n { break }
        switch frame {
        case .string(let quote):
            let c = units[i]
            if c == 0x5C /* \ */ {
                i = min(i + 2, n) // escape (also line continuations)
                continue
            }
            if quote == 0x60 /* ` */, c == 0x24 /* $ */, i + 1 < n, units[i + 1] == 0x7B /* { */ {
                stack.append(.interpolation(braceDepth: 1))
                i += 2
                continue
            }
            if c == quote {
                i += 1
                stack.removeLast()
                continue
            }
            if quote != 0x60 /* ` */, c == 0x0A /* \n */ {
                break scan // unterminated single-line string: stop here
            }
            i += 1
        case .interpolation(let depth):
            let c = units[i]
            if c == 0x7B /* { */ {
                stack[stack.count - 1] = .interpolation(braceDepth: depth + 1)
                i += 1
                continue
            }
            if c == 0x7D /* } */ {
                if depth == 1 {
                    stack.removeLast()
                } else {
                    stack[stack.count - 1] = .interpolation(braceDepth: depth - 1)
                }
                i += 1
                continue
            }
            if c == 0x22 /* " */ || c == 0x27 /* ' */ || c == 0x60 /* ` */ {
                stack.append(.string(quote: c))
                i += 1
                continue
            }
            if c == 0x2F /* / */, i + 1 < n {
                if units[i + 1] == 0x2F /* / */ {
                    i += 2
                    while i < n, units[i] != 0x0A /* \n */ { i += 1 }
                    continue
                }
                if units[i + 1] == 0x2A /* * */ {
                    i += 2
                    while i + 1 < n, !(units[i] == 0x2A && units[i + 1] == 0x2F) { i += 1 }
                    i = min(i + 2, n)
                    continue
                }
            }
            i += 1
        }
    }
    return i
}

/// Scans a regex literal starting at the opening `/` (at `start`) and
/// returns the offset one past its flags. Handles escapes and character
/// classes (`[/]` does not terminate). The regex becomes one `.string`
/// token; see the header docs for the heuristic's limits.
private func _sdkScanTSRegex(_ units: [UInt16], from start: Int) -> Int {
    var i = start + 1
    let n = units.count
    var inClass = false
    while i < n {
        let c = units[i]
        if c == 0x5C /* \ */ {
            i = min(i + 2, n)
            continue
        }
        if c == 0x0A /* \n */ { break } // unterminated: never cross lines
        if c == 0x5B /* [ */ {
            inClass = true
            i += 1
            continue
        }
        if c == 0x5D /* ] */ {
            inClass = false
            i += 1
            continue
        }
        if c == 0x2F /* / */, !inClass {
            i += 1
            break
        }
        i += 1
    }
    while i < n {
        let c = units[i]
        if (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) {
            i += 1 // flags: gimsuyd…
        } else {
            break
        }
    }
    return i
}

/// Can a `/` at this point open a regex literal? True at the start of
/// input and after anything that cannot end an expression: `(`, `,`, `=`,
/// `:`, `[`, `!`, operators, `{`, `}`, `;`, and the keywords in
/// `_sdkTSRegexAfterKeywords`. False after identifiers, numbers, `)`,
/// `]`, quotes, or non-ASCII identifier characters (conservative).
private func _sdkCanStartTSRegex(after prev: UInt16?) -> Bool {
    guard let p = prev else { return true }
    if p == 0x29 /* ) */ || p == 0x5D /* ] */ { return false }
    if p == 0x22 /* " */ || p == 0x27 /* ' */ || p == 0x60 /* ` */ { return false }
    if (p >= 0x30 && p <= 0x39) || (p >= 0x41 && p <= 0x5A) || (p >= 0x61 && p <= 0x7A)
        || p == 0x5F /* _ */ || p == 0x24 /* $ */ || p >= 0x80 {
        return false
    }
    return true
}

private func _sdkScanTypeScript(units: [UInt16], classifier: _SDKIdentifierClassifier) -> [SDKToken] {
    var tokens: [SDKToken] = []
    var i = 0
    let n = units.count
    /// Last significant (non-whitespace, non-comment) unit, for the regex
    /// heuristic. Maintained incrementally so the scan stays linear.
    var prevSig: UInt16? = nil

    while i < n {
        let c = units[i]
        // Whitespace (does not disturb prevSig)
        if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0B || c == 0x0C {
            i += 1
            continue
        }
        // Line comment
        if c == 0x2F /* / */, i + 1 < n, units[i + 1] == 0x2F {
            let start = i
            i += 2
            while i < n, units[i] != 0x0A /* \n */ { i += 1 }
            tokens.append(SDKToken(range: start..<i, kind: .comment))
            continue
        }
        // Block comment (TypeScript does NOT nest these)
        if c == 0x2F /* / */, i + 1 < n, units[i + 1] == 0x2A /* * */ {
            let start = i
            i += 2
            while i + 1 < n, !(units[i] == 0x2A && units[i + 1] == 0x2F) { i += 1 }
            i = min(i + 2, n)
            tokens.append(SDKToken(range: start..<i, kind: .comment))
            continue
        }
        // Regex literal vs. division, via the prevSig heuristic
        if c == 0x2F /* / */, _sdkCanStartTSRegex(after: prevSig) {
            let start = i
            i = _sdkScanTSRegex(units, from: i)
            tokens.append(SDKToken(range: start..<i, kind: .string))
            prevSig = 0x78 // 'x': a regex is a value, so a following '/' divides
            continue
        }
        // String literal (', ", or template `)
        if c == 0x22 /* " */ || c == 0x27 /* ' */ || c == 0x60 /* ` */ {
            let start = i
            i = _sdkScanTSString(units, from: i)
            tokens.append(SDKToken(range: start..<i, kind: .string))
            prevSig = c
            continue
        }
        // `@` decorator: @Component → .typeName
        if c == 0x40 /* @ */ {
            let start = i
            i += 1
            if i < n, classifier.isStart[i] {
                let nameStart = i
                while i < n, classifier.isContinue[i] { i += 1 }
                let kind: SDKTokenKind =
                    _sdkStartsWithUppercase(units, at: nameStart) ? .typeName : .keyword
                tokens.append(SDKToken(range: start..<i, kind: kind))
                prevSig = units[i - 1]
            } else {
                prevSig = c
            }
            continue
        }
        // `#` private field (#secret): consumed silently, no token
        if c == 0x23 /* # */ {
            var j = i + 1
            if j < n, classifier.isStart[j] {
                while j < n, classifier.isContinue[j] { j += 1 }
                prevSig = units[j - 1]
                i = j
            } else {
                prevSig = c
                i += 1
            }
            continue
        }
        // Number, including a leading-dot float (`.5`) when it cannot be
        // member access (prevSig is not an identifier char, `)`, or `]`).
        if c >= 0x30, c <= 0x39 {
            let start = i
            i = _sdkScanNumber(units, from: i)
            tokens.append(SDKToken(range: start..<i, kind: .number))
            prevSig = units[i - 1]
            continue
        }
        if c == 0x2E /* . */, i + 1 < n, units[i + 1] >= 0x30, units[i + 1] <= 0x39 {
            let p = prevSig
            let isMemberAccess: Bool = {
                guard let p else { return false }
                if p == 0x29 /* ) */ || p == 0x5D /* ] */ { return true }
                return (p >= 0x30 && p <= 0x39) || (p >= 0x41 && p <= 0x5A)
                    || (p >= 0x61 && p <= 0x7A) || p == 0x5F || p == 0x24 || p >= 0x80
            }()
            if !isMemberAccess {
                let start = i
                i += 1
                while i < n, _sdkIsNumberChar(units[i]) { i += 1 }
                tokens.append(SDKToken(range: start..<i, kind: .number))
                prevSig = units[i - 1]
                continue
            }
        }
        // Identifier: keyword, Capitalized type name, or plain
        if classifier.isStart[i] {
            let start = i
            while i < n, classifier.isContinue[i] { i += 1 }
            let word = String(decoding: units[start..<i], as: UTF16.self)
            if _sdkTypeScriptKeywords.contains(word) {
                tokens.append(SDKToken(range: start..<i, kind: .keyword))
                // A regex may follow these keywords (`return /re/`).
                prevSig = _sdkTSRegexAfterKeywords.contains(word) ? 0x3D /* = */ : units[i - 1]
            } else {
                if _sdkStartsWithUppercase(units, at: start) {
                    tokens.append(SDKToken(range: start..<i, kind: .typeName))
                }
                prevSig = units[i - 1]
            }
            continue
        }
        prevSig = c
        i += 1
    }
    return tokens
}

// MARK: - JSON scanner

/// Cheap, correct JSON: strings (with escapes), numbers (int/frac/exp),
/// and the `true`/`false`/`null` literals as keywords. Everything else
/// (braces, colons, commas, whitespace) is plain.
private func _sdkScanJSONNumber(_ units: [UInt16], from start: Int) -> Int {
    var i = start
    let n = units.count
    if i < n, units[i] == 0x2D /* - */ { i += 1 }
    while i < n, units[i] >= 0x30, units[i] <= 0x39 { i += 1 }
    if i < n, units[i] == 0x2E /* . */ {
        i += 1
        while i < n, units[i] >= 0x30, units[i] <= 0x39 { i += 1 }
    }
    if i < n, units[i] == 0x65 /* e */ || units[i] == 0x45 /* E */ {
        var j = i + 1
        if j < n, units[j] == 0x2B /* + */ || units[j] == 0x2D /* - */ { j += 1 }
        if j < n, units[j] >= 0x30, units[j] <= 0x39 {
            i = j + 1
            while i < n, units[i] >= 0x30, units[i] <= 0x39 { i += 1 }
        }
    }
    return i
}

private func _sdkScanJSON(units: [UInt16], classifier: _SDKIdentifierClassifier) -> [SDKToken] {
    var tokens: [SDKToken] = []
    var i = 0
    let n = units.count
    while i < n {
        let c = units[i]
        if c == 0x22 /* " */ {
            let start = i
            i += 1
            while i < n {
                if units[i] == 0x5C /* \ */ {
                    i = min(i + 2, n)
                    continue
                }
                if units[i] == 0x22 /* " */ {
                    i += 1
                    break
                }
                i += 1
            }
            tokens.append(SDKToken(range: start..<i, kind: .string))
            continue
        }
        if c == 0x2D /* - */ || (c >= 0x30 && c <= 0x39) {
            let start = i
            i = _sdkScanJSONNumber(units, from: i)
            tokens.append(SDKToken(range: start..<i, kind: .number))
            continue
        }
        if classifier.isStart[i] {
            let start = i
            while i < n, classifier.isContinue[i] { i += 1 }
            let word = String(decoding: units[start..<i], as: UTF16.self)
            if word == "true" || word == "false" || word == "null" {
                tokens.append(SDKToken(range: start..<i, kind: .keyword))
            }
            continue
        }
        i += 1
    }
    return tokens
}

// MARK: - Markdown scanner

/// Shallow but correct Markdown: `#` heading markers and `-`/`+`/`*`
/// list markers as keywords; fenced code blocks and inline code spans as
/// strings; link destinations as strings; `<!-- … -->` as comments.
/// Emphasis markers are left plain.
private func _sdkStartsFence(_ units: [UInt16], at i: Int) -> Bool {
    i + 2 < units.count && units[i] == 0x60 /* ` */ && units[i + 1] == 0x60 && units[i + 2] == 0x60
}

private func _sdkScanMarkdown(units: [UInt16]) -> [SDKToken] {
    var tokens: [SDKToken] = []
    var i = 0
    let n = units.count
    var atLineStart = true
    while i < n {
        let c = units[i]
        if c == 0x0A /* \n */ {
            atLineStart = true
            i += 1
            continue
        }
        // Fenced code block: from opening fence through the closing fence
        if atLineStart, _sdkStartsFence(units, at: i) {
            let start = i
            i += 3
            while i < n, units[i] != 0x0A /* \n */ { i += 1 } // info string
            while i < n {
                if units[i] == 0x0A /* \n */ {
                    i += 1 // now at a line start
                    continue
                }
                if _sdkStartsFence(units, at: i) {
                    i += 3
                    break
                }
                while i < n, units[i] != 0x0A /* \n */ { i += 1 }
            }
            tokens.append(SDKToken(range: start..<i, kind: .string))
            atLineStart = false
            continue
        }
        // Heading marker: 1–6 '#' followed by space/tab
        if atLineStart, c == 0x23 /* # */ {
            var j = i
            while j < n, units[j] == 0x23 /* # */ { j += 1 }
            if j - i <= 6, j < n, units[j] == 0x20 || units[j] == 0x09 {
                tokens.append(SDKToken(range: i..<j, kind: .keyword))
                i = j
                atLineStart = false
                continue
            }
        }
        // Unordered list marker at line start
        if atLineStart, (c == 0x2D /* - */ || c == 0x2A /* * */ || c == 0x2B /* + */),
           i + 1 < n, units[i + 1] == 0x20 || units[i + 1] == 0x09 {
            tokens.append(SDKToken(range: i..<(i + 1), kind: .keyword))
            i += 1
            atLineStart = false
            continue
        }
        // Inline code span: matching backtick run, single line
        if c == 0x60 /* ` */ {
            let start = i
            var openLen = 0
            while i < n, units[i] == 0x60 /* ` */ {
                openLen += 1
                i += 1
            }
            var j = i
            var closedAt: Int? = nil
            while j < n, units[j] != 0x0A /* \n */ {
                if units[j] == 0x60 /* ` */ {
                    var k = j
                    while k < n, units[k] == 0x60 /* ` */ { k += 1 }
                    if k - j == openLen {
                        closedAt = k
                        break
                    }
                    j = k
                } else {
                    j += 1
                }
            }
            if let end = closedAt {
                tokens.append(SDKToken(range: start..<end, kind: .string))
                i = end
            }
            atLineStart = false
            continue
        }
        // Link destination: [text](url)
        if c == 0x5D /* ] */, i + 1 < n, units[i + 1] == 0x28 /* ( */ {
            var j = i + 2
            while j < n, units[j] != 0x0A /* \n */, units[j] != 0x29 /* ) */ { j += 1 }
            if j < n, units[j] == 0x29 /* ) */ {
                tokens.append(SDKToken(range: (i + 2)..<j, kind: .string))
                i = j + 1
                atLineStart = false
                continue
            }
        }
        // HTML comment
        if c == 0x3C /* < */, i + 3 < n,
           units[i + 1] == 0x21 /* ! */, units[i + 2] == 0x2D /* - */, units[i + 3] == 0x2D {
            let start = i
            i += 4
            while i + 2 < n, !(units[i] == 0x2D && units[i + 1] == 0x2D && units[i + 2] == 0x3E /* > */) {
                i += 1
            }
            i = min(i + 3, n)
            tokens.append(SDKToken(range: start..<i, kind: .comment))
            atLineStart = false
            continue
        }
        atLineStart = false
        i += 1
    }
    return tokens
}
