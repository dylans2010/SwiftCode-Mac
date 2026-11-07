import Foundation
import SwiftCodeIDECore
import SwiftCodeSyntax

public struct SourceRun: Equatable, Sendable {
    public var text: String
    public var role: SyntaxTokenKind.Role?
    public init(_ text: String, role: SyntaxTokenKind.Role? = nil) {
        self.text = text
        self.role = role
    }
}

public struct SourceLine: Identifiable, Equatable, Sendable {
    public var number: Int
    public var runs: [SourceRun]
    public var id: Int { number }
    public var text: String { runs.map(\.text).joined() }
    public init(number: Int, runs: [SourceRun]) {
        self.number = number
        self.runs = runs
    }
}

public struct SourceDocument: Equatable, Sendable {
    public var path: String
    public var language: SyntaxLanguage
    public var lines: [SourceLine]
    public var message: String?
    public var name: String { (path as NSString).lastPathComponent }

    public static let highlightLimit = 20_000
    public static let sizeLimit = 8 << 20
    public static let tabWidth = 4

    public init(path: String, language: SyntaxLanguage, lines: [SourceLine], message: String? = nil) {
        self.path = path
        self.language = language
        self.lines = lines
        self.message = message
    }

    public static func load(path: String) -> SourceDocument {
        let language = SyntaxLanguage(fileName: (path as NSString).lastPathComponent)
        guard let data = FileManager.default.contents(atPath: path) else {
            return SourceDocument(path: path, language: language, lines: [], message: "Cannot read \((path as NSString).lastPathComponent)")
        }
        if data.count > sizeLimit {
            return SourceDocument(path: path, language: language, lines: [], message: "File too large to show (\(data.count / 1024) KB)")
        }
        if data.prefix(8192).contains(0) || FindEngine.binaryExtensions.contains((path as NSString).pathExtension.lowercased()) {
            return SourceDocument(path: path, language: language, lines: [], message: "Binary file")
        }
        let text = String(decoding: data, as: UTF8.self)
        return SourceDocument(path: path, language: language, lines: highlight(text, language: language))
    }

    public static func highlight(_ text: String, language: SyntaxLanguage) -> [SourceLine] {
        let units = Array(text.utf16)
        var starts = [0]
        for (i, u) in units.enumerated() where u == 0x0A { starts.append(i + 1) }
        if starts.count > 1, starts.last == units.count { starts.removeLast() }
        let lineCount = units.isEmpty ? 1 : starts.count
        let doc: SyntaxDocument? = lineCount <= highlightLimit ? SyntaxDocument(text: text, language: language) : nil
        var lines: [SourceLine] = []
        lines.reserveCapacity(lineCount)
        for n in 0..<lineCount {
            let start = starts[n]
            var end = n + 1 < starts.count ? starts[n + 1] : units.count
            if end > start, units[end - 1] == 0x0A { end -= 1 }
            if end > start, units[end - 1] == 0x0D { end -= 1 }
            let tokens = doc.map { d in n < d.lineCount ? d.tokens(onLine: n) : [] } ?? []
            lines.append(SourceLine(number: n + 1, runs: runs(units, start..<end, tokens: tokens)))
        }
        return lines
    }

    static func runs(_ units: [UInt16], _ line: Range<Int>, tokens: [SyntaxToken]) -> [SourceRun] {
        var out: [SourceRun] = []
        var column = 0
        func add(_ r: Range<Int>, _ role: SyntaxTokenKind.Role?) {
            guard !r.isEmpty else { return }
            let s = expandTabs(String(decoding: units[r], as: UTF16.self), column: &column)
            if let last = out.last, last.role == role {
                out[out.count - 1].text += s
            } else {
                out.append(SourceRun(s, role: role))
            }
        }
        var at = line.lowerBound
        for t in tokens.sorted(by: { $0.location < $1.location }) {
            let a = max(t.location, at), b = min(t.end, line.upperBound)
            guard a < b else { continue }
            add(at..<a, nil)
            let role = t.kind.role == .identifier ? nil : t.kind.role
            add(a..<b, role)
            at = b
        }
        add(at..<line.upperBound, nil)
        return out
    }

    static func expandTabs(_ s: String, column: inout Int) -> String {
        guard s.contains("\t") else {
            column += s.count
            return s
        }
        var out = ""
        for ch in s {
            if ch == "\t" {
                let n = tabWidth - column % tabWidth
                out += String(repeating: " ", count: n)
                column += n
            } else {
                out.append(ch)
                column += 1
            }
        }
        return out
    }
}

public struct SourcePalette: Equatable, Sendable {
    public var background: ThemeColor
    public var foreground: ThemeColor
    public var currentLine: ThemeColor
    public var lineNumber: ThemeColor
    public var selection: ThemeColor
    public var tokens: [SyntaxTokenKind.Role: ThemeColor]

    public static func forAppearance(dark: Bool, theme: EditorTheme? = nil) -> SourcePalette {
        let theme = theme ?? EditorTheme.builtIns[0]
        let base = WorkspaceChrome.defaultThemeColors(dark: dark)
        let bg = ThemeColor(hex: theme.background) ?? base.background
        let fg = ThemeColor(hex: theme.foreground) ?? base.foreground
        var tokens: [SyntaxTokenKind.Role: ThemeColor] = [:]
        for role in SyntaxTokenKind.Role.allCases {
            if let c = ThemeColor(hex: theme.tokens[role.rawValue]) ?? base.tokens[role.rawValue] { tokens[role] = c }
        }
        let own = theme.background != nil
        return SourcePalette(background: bg, foreground: fg, currentLine: ThemeColor(hex: theme.currentLine) ?? base.currentLine,
                             lineNumber: own ? mix(fg, bg, 0.45) : base.lineNumber,
                             selection: ThemeColor(hex: theme.selection) ?? base.selection, tokens: tokens)
    }

    public func color(_ role: SyntaxTokenKind.Role?) -> ThemeColor {
        role.flatMap { tokens[$0] } ?? foreground
    }

    static func mix(_ a: ThemeColor, _ b: ThemeColor, _ t: Double) -> ThemeColor {
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Double(x) * (1 - t) + Double(y) * t).rounded()) }
        return ThemeColor(red: m(a.red, b.red), green: m(a.green, b.green), blue: m(a.blue, b.blue))
    }
}
