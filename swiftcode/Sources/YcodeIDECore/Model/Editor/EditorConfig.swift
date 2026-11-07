import Foundation

public struct EditorConfig: Equatable, Sendable {
    public enum IndentStyle: String, Sendable { case space, tab }

    public var indentStyle: IndentStyle?
    public var indentSize: Int?
    public var tabWidth: Int?
    public var sources: [String] = []

    public init(indentStyle: IndentStyle? = nil, indentSize: Int? = nil, tabWidth: Int? = nil) {
        self.indentStyle = indentStyle
        self.indentSize = indentSize
        self.tabWidth = tabWidth
    }

    public var providesIndentation: Bool { indentStyle != nil || indentSize != nil || tabWidth != nil }

    public static let indentationNote = "Indentation settings provided by EditorConfig"

    public static func settings(for file: URL, read: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }) -> EditorConfig {
        let real = file.standardizedFileURL.resolvingSymlinksInPath()
        let found = lookUp(real, read: read)
        if !found.providesIndentation, real.path != file.standardizedFileURL.path { return lookUp(file, read: read) }
        return found
    }

    static func lookUp(_ file: URL, read: (String) -> String?) -> EditorConfig {
        var dir = file.standardizedFileURL.deletingLastPathComponent()
        var chain: [(dir: String, text: String)] = []
        while true {
            let path = dir.appendingPathComponent(".editorconfig").path
            if let text = read(path) {
                chain.append((dir.path, text))
                if isRoot(text) { break }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path || dir.path == "/" { break }
            dir = parent
        }
        var props: [String: String] = [:]
        var out = EditorConfig()
        for (d, text) in chain.reversed() {
            let rel = String(file.standardizedFileURL.path.dropFirst(d.count + (d.hasSuffix("/") ? 0 : 1)))
            for (glob, pairs) in sections(text) where matches(glob, rel) {
                for (k, v) in pairs { props[k] = v }
            }
            out.sources.insert(d + "/.editorconfig", at: 0)
        }
        out.indentStyle = props["indent_style"].flatMap(IndentStyle.init(rawValue:))
        if let s = props["indent_size"] { out.indentSize = Int(s) }
        if let s = props["tab_width"] { out.tabWidth = Int(s) }
        if out.tabWidth == nil, let size = out.indentSize { out.tabWidth = size }
        if out.indentSize == nil, props["indent_size"] == "tab" { out.indentSize = out.tabWidth }
        if !out.providesIndentation { out.sources = [] }
        return out
    }

    static func isRoot(_ text: String) -> Bool {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return false }
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if kv.count == 2, kv[0] == "root" { return kv[1] == "true" }
        }
        return false
    }

    static func sections(_ text: String) -> [(String, [(String, String)])] {
        var out: [(String, [(String, String)])] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                out.append((String(line.dropFirst().dropLast()), []))
                continue
            }
            guard !out.isEmpty else { continue }
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2 { out[out.count - 1].1.append((kv[0].lowercased(), kv[1].lowercased())) }
        }
        return out
    }

    static func matches(_ glob: String, _ path: String) -> Bool {
        let anchored = glob.contains("/")
        let pattern = glob.hasPrefix("/") ? String(glob.dropFirst()) : glob
        let target = anchored ? path : (path.split(separator: "/").last.map(String.init) ?? path)
        guard let re = try? NSRegularExpression(pattern: "^" + regex(pattern) + "$") else { return false }
        return re.firstMatch(in: target, range: NSRange(target.startIndex..., in: target)) != nil
    }

    static func regex(_ glob: String) -> String {
        var out = ""
        var chars = Array(glob)[...]
        var braces = 0
        while let c = chars.popFirst() {
            switch c {
            case "*":
                if chars.first == "*" { chars.removeFirst(); out += ".*" } else { out += "[^/]*" }
            case "?": out += "[^/]"
            case "[":
                var cls = "["
                while let d = chars.popFirst(), d != "]" { cls += d == "!" && cls == "[" ? "^" : String(d) }
                out += cls + "]"
            case "{": braces += 1; out += "(?:"
            case "}" where braces > 0: braces -= 1; out += ")"
            case "," where braces > 0: out += "|"
            default: out += NSRegularExpression.escapedPattern(for: String(c))
            }
        }
        return out
    }
}
