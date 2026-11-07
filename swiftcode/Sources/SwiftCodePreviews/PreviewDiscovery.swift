import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct PreviewDeclaration: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case macro(body: String)
        case provider(type: String)
    }

    public var name: String
    public var kind: Kind
    public var fixedSize: CGSize?
    public var line: Int
    public var range: NSRange?
    public var isNamed: Bool = true
    public var traits: [String] = []
    public var bodyLine: Int

    public init(name: String, kind: Kind, fixedSize: CGSize?, line: Int, range: NSRange?, isNamed: Bool = true, traits: [String] = [],
                bodyLine: Int? = nil) {
        self.name = name
        self.kind = kind
        self.fixedSize = fixedSize
        self.line = line
        self.range = range
        self.isNamed = isNamed
        self.traits = traits
        self.bodyLine = bodyLine ?? line
    }

    public var layout: PreviewLayoutTrait {
        if let s = fixedSize { return .fixed(s) }
        return traits.contains("sizeThatFitsLayout") ? .sizeThatFits : .device
    }

    public var orientation: PreviewOrientation {
        for t in traits { if let o = PreviewOrientation(rawValue: t) { return o } }
        return .portrait
    }

    public var tabTitle: String {
        guard !isNamed, case .macro(let body) = kind else { return name }
        return PreviewDiscovery.leadingViewType(body) ?? name
    }
}

public enum PreviewLayoutTrait: Equatable, Sendable {
    case device
    case sizeThatFits
    case fixed(CGSize)
}

public enum PreviewOrientation: String, Equatable, Sendable, CaseIterable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight
    public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
}

public enum PreviewDiscovery {
    public static func previews(in text: String) -> [PreviewDeclaration] {
        let s = Array(text.utf16)
        var out: [PreviewDeclaration] = []
        var i = 0
        var unnamed = 0
        func line(_ at: Int) -> Int { s[..<at].filter { $0 == 10 }.count + 1 }
        func skipSpace(_ j: inout Int) { while j < s.count, [32, 9, 10, 13].contains(s[j]) { j += 1 } }
        while i < s.count {
            if s[i] == 47, i + 1 < s.count, s[i + 1] == 47 { while i < s.count, s[i] != 10 { i += 1 }; continue }
            if s[i] == 47, i + 1 < s.count, s[i + 1] == 42 { i = closeComment(s, i); continue }
            if s[i] == 34 { i = closeString(s, i); continue }
            if matches(s, i, "#Preview"), !isIdent(s, i + 8) {
                let start = i
                var j = i + 8
                skipSpace(&j)
                var name: String?
                var size: CGSize?
                var traits: [String] = []
                if j < s.count, s[j] == 40  {
                    let close = matching(s, j, open: 40, close: 41)
                    let args = String(utf16CodeUnits: Array(s[(j + 1)..<max(j + 1, close - 1)]), count: max(0, close - 1 - (j + 1)))
                    name = firstStringLiteral(args)
                    size = fixedLayout(args)
                    traits = traitNames(args)
                    j = close
                    skipSpace(&j)
                }
                guard j < s.count, s[j] == 123  else { i = j; continue }
                let end = matching(s, j, open: 123, close: 125)
                let body = String(utf16CodeUnits: Array(s[(j + 1)..<(end - 1)]), count: end - 1 - (j + 1))
                let named = name != nil
                if name == nil { unnamed += 1; name = unnamed == 1 ? "Preview" : "Preview \(unnamed)" }
                out.append(PreviewDeclaration(name: name!, kind: .macro(body: body), fixedSize: size, line: line(start),
                                              range: NSRange(location: start, length: end - start), isNamed: named, traits: traits,
                                              bodyLine: line(j)))
                i = end
                continue
            }
            i += 1
        }
        let code = codeOnly(text)
        let ns = code as NSString
        if let re = try? NSRegularExpression(pattern: "(?m)^\\s*(?:public\\s+|internal\\s+)?struct\\s+(\\w+)\\s*:[^{]*\\bPreviewProvider\\b") {
            for m in re.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                let type = ns.substring(with: m.range(at: 1))
                out.append(PreviewDeclaration(name: type, kind: .provider(type: type), fixedSize: nil,
                                              line: ns.substring(to: m.range.location).filter { $0 == "\n" }.count + 1, range: nil))
            }
        }
        return out.sorted { $0.line < $1.line }
    }

    public static func leadingViewType(_ body: String) -> String? {
        let code = codeOnly(body)
        for raw in code.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("@") || line.hasPrefix("let ") || line.hasPrefix("var ") { continue }
            let l = line.hasPrefix("return ") ? String(line.dropFirst(7)) : line
            guard let re = try? NSRegularExpression(pattern: "^([A-Z][A-Za-z0-9_]*)\\s*[({]"),
                  let m = re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) else { return nil }
            return (l as NSString).substring(with: m.range(at: 1))
        }
        return nil
    }

    public static func codeOnly(_ text: String) -> String {
        var s = Array(text.utf16)
        var i = 0
        func blank(_ a: Int, _ b: Int) { for k in a..<min(b, s.count) where s[k] != 10 { s[k] = 32 } }
        while i < s.count {
            if s[i] == 47, i + 1 < s.count, s[i + 1] == 47 {
                var j = i; while j < s.count, s[j] != 10 { j += 1 }; blank(i, j); i = j; continue
            }
            if s[i] == 47, i + 1 < s.count, s[i + 1] == 42 { let j = closeComment(s, i); blank(i, j); i = j; continue }
            if s[i] == 34 { let j = closeString(s, i); blank(i, j); i = j; continue }
            i += 1
        }
        return String(utf16CodeUnits: s, count: s.count)
    }

    static func matches(_ s: [UInt16], _ i: Int, _ word: String) -> Bool {
        let w = Array(word.utf16)
        return i + w.count <= s.count && Array(s[i..<i + w.count]) == w
    }

    static func isIdent(_ s: [UInt16], _ i: Int) -> Bool {
        guard i < s.count, let u = Unicode.Scalar(s[i]) else { return false }
        return CharacterSet.alphanumerics.contains(u) || s[i] == 95
    }

    static func closeComment(_ s: [UInt16], _ i: Int) -> Int {
        var j = i + 2, depth = 1
        while j + 1 < s.count, depth > 0 {
            if s[j] == 47, s[j + 1] == 42 { depth += 1; j += 2 } else if s[j] == 42, s[j + 1] == 47 { depth -= 1; j += 2 } else { j += 1 }
        }
        return j
    }

    static func closeString(_ s: [UInt16], _ i: Int) -> Int {
        if matches(s, i, "\"\"\"") {
            var j = i + 3
            while j < s.count, !matches(s, j, "\"\"\"") { j += s[j] == 92 ? 2 : 1 }
            return min(s.count, j + 3)
        }
        var j = i + 1
        while j < s.count, s[j] != 34, s[j] != 10 { j += s[j] == 92 ? 2 : 1 }
        return min(s.count, j + 1)
    }

    static func matching(_ s: [UInt16], _ i: Int, open: UInt16, close: UInt16) -> Int {
        var j = i + 1, depth = 1
        while j < s.count {
            if s[j] == 47, j + 1 < s.count, s[j + 1] == 47 { while j < s.count, s[j] != 10 { j += 1 }; continue }
            if s[j] == 47, j + 1 < s.count, s[j + 1] == 42 { j = closeComment(s, j); continue }
            if s[j] == 34 { j = closeString(s, j); continue }
            if s[j] == open { depth += 1 } else if s[j] == close { depth -= 1; if depth == 0 { return j + 1 } }
            j += 1
        }
        return s.count
    }

    static func firstStringLiteral(_ args: String) -> String? {
        guard let a = args.firstIndex(of: "\"") else { return nil }
        guard args[..<a].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var out = ""
        var it = args[args.index(after: a)...].makeIterator()
        while let c = it.next() {
            if c == "\"" { return out }
            if c == "\\", let n = it.next() {
                switch n { case "n": out.append("\n"); case "t": out.append("\t"); default: out.append(n) }
                continue
            }
            out.append(c)
        }
        return nil
    }

    static func traitNames(_ args: String) -> [String] {
        let code = codeOnly(args)
        guard let r = code.range(of: "traits:") else { return [] }
        let tail = String(code[r.upperBound...])
        guard let re = try? NSRegularExpression(pattern: "(?:^|[,\\s])\\.([A-Za-z_][A-Za-z0-9_]*)") else { return [] }
        var out: [String] = []
        var depth = 0
        var flat = ""
        for c in tail {
            if c == "(" { depth += 1; if depth == 1 { flat.append(" ") }; continue }
            if c == ")" { depth -= 1; continue }
            if depth == 0 { flat.append(c) }
        }
        let ns = flat as NSString
        for m in re.matches(in: flat, range: NSRange(location: 0, length: ns.length)) { out.append(ns.substring(with: m.range(at: 1))) }
        return out
    }

    static func fixedLayout(_ args: String) -> CGSize? {
        guard let re = try? NSRegularExpression(pattern: "\\.fixedLayout\\s*\\(\\s*width:\\s*([0-9.]+)\\s*,\\s*height:\\s*([0-9.]+)"),
              let m = re.firstMatch(in: args, range: NSRange(args.startIndex..., in: args)),
              let w = Double((args as NSString).substring(with: m.range(at: 1))),
              let h = Double((args as NSString).substring(with: m.range(at: 2))) else { return nil }
        return CGSize(width: w, height: h)
    }

    public static func blankingPreviewsAndEntryPoints(_ text: String) -> String {
        var units = Array(blankingPreviews(text).utf16)
        let code = Array(codeOnly(String(utf16CodeUnits: units, count: units.count)).utf16)
        for word in ["@main", "@UIApplicationMain", "@NSApplicationMain"] {
            let w = Array(word.utf16)
            var i = 0
            while i + w.count <= code.count {
                if Array(code[i..<i + w.count]) == w, !isIdent(code, i + w.count) {
                    for k in i..<i + w.count { units[k] = 32 }
                    i += w.count
                } else { i += 1 }
            }
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    public static func blankingPreviews(_ text: String) -> String {
        var units = Array(text.utf16)
        for p in previews(in: text) {
            guard let r = p.range else { continue }
            for k in r.location..<(r.location + r.length) where units[k] != 10 { units[k] = 32 }
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}

extension PreviewDiscovery {
    public static func needsUIKit(text: String, previews: [PreviewDeclaration]? = nil) -> Bool {
        let code = codeOnly(text)
        for line in code.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "import UIKit" || t.hasPrefix("import UIKit.") || t.hasSuffix(" import UIKit") { return true }
        }
        for p in previews ?? self.previews(in: text) {
            guard case .macro(let body) = p.kind else { continue }
            if codeOnly(body).range(of: #"\bUI[A-Z][A-Za-z]*(View|Controller|Label|Button|Field|Switch|Slider|Stepper|Picker|Control|Bar)\b"#,
                                    options: .regularExpression) != nil { return true }
        }
        return false
    }
}

public enum CanvasAutoShow {
    public enum Decision: Equatable, Sendable { case show, hide, keep }

    public static func hasPreviews(fileName: String, text: String) -> Bool {
        guard (fileName as NSString).pathExtension == "swift",
              text.contains("#Preview") || text.contains("PreviewProvider") else { return false }
        return !PreviewDiscovery.previews(in: text).isEmpty
    }

    public static func decide(hasPreviews: Bool, canvasShown: Bool, canvasMode: Bool) -> Decision {
        let draw = canvasMode && hasPreviews
        if draw == canvasShown { return .keep }
        return draw ? .show : .hide
    }
}
