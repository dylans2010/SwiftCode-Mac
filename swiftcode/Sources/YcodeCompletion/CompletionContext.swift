import Foundation

public struct ContextLimits: Sendable, Equatable {
    public var prefixTokens: Int
    public var suffixTokens: Int
    public var relatedTokens: Int
    public var maxRelated: Int
    public static let charactersPerToken = 3

    public init(prefixTokens: Int = 1536, suffixTokens: Int = 512, relatedTokens: Int = 512, maxRelated: Int = 3) {
        self.prefixTokens = prefixTokens
        self.suffixTokens = suffixTokens
        self.relatedTokens = relatedTokens
        self.maxRelated = maxRelated
    }

    public static func characters(_ tokens: Int) -> Int { max(0, tokens) * charactersPerToken }
    public static func estimatedTokens(_ s: String) -> Int { (s.utf16.count + charactersPerToken - 1) / charactersPerToken }
}

public struct RelatedSnippet: Sendable, Equatable, Codable {
    public var path: String
    public var text: String
    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

public struct CompletionContext: Sendable, Equatable {
    public var prefix: String
    public var suffix: String
    public var path: String
    public var language: String?
    public var related: [RelatedSnippet]
    public var linePrefix: String
    public var lineSuffix: String
    public var prefixIsWholeFile: Bool

    public init(prefix: String, suffix: String, path: String, language: String? = nil, related: [RelatedSnippet] = [],
                linePrefix: String? = nil, lineSuffix: String? = nil, prefixIsWholeFile: Bool = true) {
        self.prefix = prefix
        self.suffix = suffix
        self.path = path
        self.language = language
        self.related = related
        self.linePrefix = linePrefix ?? String(prefix.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")
        self.lineSuffix = lineSuffix ?? String(suffix.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        self.prefixIsWholeFile = prefixIsWholeFile
    }

    public var suffixAfterLine: String {
        guard let nl = suffix.firstIndex(of: "\n") else { return "" }
        return String(suffix[suffix.index(after: nl)...])
    }

    public var isMidLine: Bool {
        !lineSuffix.allSatisfy { " \t)]}>\"'`;,.".contains($0) }
    }

    public static func make(text: String, caret: Int, path: String, language: String? = nil,
                            related: [RelatedSnippet] = [], limits: ContextLimits = ContextLimits()) -> CompletionContext {
        let ns = text as NSString
        let c = max(0, min(caret, ns.length))
        let before = ns.substring(to: c), after = ns.substring(from: c)
        let lineStart = (before as NSString).range(of: "\n", options: .backwards).location
        let linePrefix = lineStart == NSNotFound ? before : (before as NSString).substring(from: lineStart + 1)
        let lineEnd = (after as NSString).range(of: "\n").location
        let lineSuffix = lineEnd == NSNotFound ? after : (after as NSString).substring(to: lineEnd)
        let (prefix, whole) = Self.tail(before, maxCharacters: ContextLimits.characters(limits.prefixTokens), keeping: linePrefix)
        let suffix = Self.head(after, maxCharacters: ContextLimits.characters(limits.suffixTokens), keeping: lineSuffix)
        let budget = ContextLimits.characters(limits.relatedTokens)
        var kept: [RelatedSnippet] = []
        var used = 0
        for r in related.prefix(limits.maxRelated) {
            let n = r.text.utf16.count + r.path.utf16.count + 2
            guard used + n <= budget else { continue }
            kept.append(r)
            used += n
        }
        return CompletionContext(prefix: prefix, suffix: suffix, path: path, language: language ?? Self.language(forPath: path), related: kept,
                                 linePrefix: linePrefix, lineSuffix: lineSuffix, prefixIsWholeFile: whole)
    }

    static func tail(_ s: String, maxCharacters: Int, keeping: String) -> (String, Bool) {
        let ns = s as NSString
        guard ns.length > maxCharacters else { return (s, true) }
        let keep = (keeping as NSString).length
        var start = ns.length - max(maxCharacters, keep)
        let nl = ns.range(of: "\n", options: [], range: NSRange(location: start, length: ns.length - start)).location
        if nl != NSNotFound, nl + 1 <= ns.length - keep { start = nl + 1 }
        return (ns.substring(from: start), false)
    }

    static func head(_ s: String, maxCharacters: Int, keeping: String) -> String {
        let ns = s as NSString
        guard ns.length > maxCharacters else { return s }
        let keep = (keeping as NSString).length
        let end = max(maxCharacters, keep)
        let nl = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: end)).location
        return ns.substring(to: nl != NSNotFound && nl >= keep ? nl + 1 : end)
    }

    public static func language(forPath path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        let table: [String: String] = [
            "swift": "swift", "m": "objective-c", "mm": "objective-cpp", "h": "c", "c": "c", "cc": "cpp", "cpp": "cpp", "cxx": "cpp",
            "hpp": "cpp", "metal": "metal", "py": "python", "js": "javascript", "ts": "typescript", "rb": "ruby", "rs": "rust",
            "go": "go", "java": "java", "kt": "kotlin", "sh": "shell", "json": "json", "plist": "xml", "xml": "xml", "md": "markdown",
            "yml": "yaml", "yaml": "yaml", "html": "html", "css": "css", "sql": "sql",
        ]
        return table[ext]
    }

    public static func lineComment(for language: String?) -> String? {
        switch language {
        case "swift", "objective-c", "objective-cpp", "c", "cpp", "metal", "javascript", "typescript", "rust", "go", "java", "kotlin": "//"
        case "python", "ruby", "shell", "yaml": "#"
        case "sql": "--"
        default: nil
        }
    }

    public static func offset(in text: String, line: Int, column: Int) -> Int? {
        guard line >= 1 else { return nil }
        var offset = 0
        var current = 1
        for l in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if current == line {
                let chars = Array(l)
                let n = max(0, min(column - 1, chars.count))
                return offset + String(chars[0..<n]).utf16.count
            }
            offset += l.utf16.count + 1
            current += 1
        }
        return nil
    }
}

public enum RelatedSnippets {
    public static func pick(query: String, files: [(path: String, text: String)], windowLines: Int = 20,
                            limit: Int = 3, minimumScore: Double = 0.1) -> [RelatedSnippet] {
        let q = identifiers(String(query.split(separator: "\n", omittingEmptySubsequences: false).suffix(windowLines).joined(separator: "\n")))
        guard !q.isEmpty else { return [] }
        var scored: [(Double, RelatedSnippet)] = []
        for f in files {
            let lines = f.text.split(separator: "\n", omittingEmptySubsequences: false)
            var best: (Double, String)?
            var i = 0
            repeat {
                let window = lines[i..<min(lines.count, i + windowLines)].joined(separator: "\n")
                let ids = identifiers(window)
                let inter = ids.intersection(q).count
                let score = ids.isEmpty ? 0 : Double(inter) / Double(ids.union(q).count)
                if score > (best?.0 ?? 0) { best = (score, window) }
                i += max(1, windowLines / 2)
            } while i < lines.count
            if let b = best, b.0 >= minimumScore { scored.append((b.0, RelatedSnippet(path: f.path, text: b.1))) }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1)
    }

    static func identifiers(_ s: String) -> Set<String> {
        var out = Set<String>()
        var cur = ""
        func flush() {
            if cur.count >= 3, !keywords.contains(cur), !(cur.first?.isNumber ?? false) { out.insert(cur) }
            cur = ""
        }
        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "_" { cur.append(ch) } else { flush() }
        }
        flush()
        return out
    }

    static let keywords: Set<String> = ["let", "var", "func", "return", "if", "else", "for", "while", "import", "struct", "class", "enum",
                                        "self", "Self", "true", "false", "nil", "public", "private", "internal", "static", "case", "switch",
                                        "guard", "init", "the", "and", "void", "int", "const", "extension", "protocol", "throws", "try", "await", "async"]
}
