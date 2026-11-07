import Foundation
import YcodeLanguage

public enum TextEditApplication {
    public static func ranges(_ edits: [TextEdit], in text: String) -> [(range: NSRange, newText: String)] {
        let index = LineIndex(text)
        return edits.map { e in
            let a = index.offset(of: e.start), b = index.offset(of: e.end)
            return (NSRange(location: a, length: max(0, b - a)), e.newText)
        }
    }

    public static func apply(_ edits: [TextEdit], to text: String) -> String {
        let ns = NSMutableString(string: text)
        for r in ranges(edits, in: text).sorted(by: { $0.range.location > $1.range.location }) {
            ns.replaceCharacters(in: r.range, with: r.newText)
        }
        return ns as String
    }
}

public struct RenamePreview: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var line: Int
        public var before: String
        public var after: String
    }

    public struct File: Equatable, Sendable {
        public var path: String
        public var editCount: Int
        public var lines: [Line]
        public var name: String { (path as NSString).lastPathComponent }
        public var countText: String { "\(editCount) change\(editCount == 1 ? "" : "s")" }
    }

    public var oldName: String
    public var newName: String
    public var edit: WorkspaceEdit
    public var files: [File]

    public init(edit: WorkspaceEdit, oldName: String, newName: String, text: (URL) -> String?) {
        self.oldName = oldName
        self.newName = newName
        self.edit = edit
        files = edit.files.compactMap { url in
            let edits = edit.changes[url] ?? []
            guard !edits.isEmpty else { return nil }
            let path = url.standardizedFileURL.path
            guard let old = text(url) else { return File(path: path, editCount: edits.count, lines: []) }
            let new = TextEditApplication.apply(edits, to: old)
            let oldLines = old.components(separatedBy: "\n"), newLines = new.components(separatedBy: "\n")
            let touched = Set(edits.flatMap { $0.start.line...max($0.start.line, $0.end.line) }).sorted()
            let lines = touched.compactMap { n -> Line? in
                guard n < oldLines.count else { return nil }
                let after = oldLines.count == newLines.count && n < newLines.count ? newLines[n] : oldLines[n]
                return Line(line: n + 1, before: oldLines[n].trimmingCharacters(in: .whitespaces),
                            after: after.trimmingCharacters(in: .whitespaces))
            }
            return File(path: path, editCount: edits.count, lines: lines)
        }
    }

    public var editCount: Int { files.reduce(0) { $0 + $1.editCount } }

    public var summary: String {
        let n = editCount, f = files.count
        return "Rename \(n) occurrence\(n == 1 ? "" : "s") in \(f) file\(f == 1 ? "" : "s")"
    }
}

public enum SymbolResults {
    public static func referencesTitle(_ name: String, count: Int) -> String {
        "\(name) — \(count) reference\(count == 1 ? "" : "s")"
    }

    public static func callersTitle(_ name: String) -> String { "Callers of \(name)" }

    public static func fileResults(_ locations: [Location], text: (String) -> String?) -> [WorkspaceSearch.FileResult] {
        let byFile = Dictionary(grouping: locations) { $0.url.standardizedFileURL.path }
        return byFile.keys.sorted().map { path in
            let source = text(path) ?? ""
            let index = LineIndex(source)
            let ns = source as NSString
            var seen = Set<Position>()
            let locs = byFile[path]!.filter { seen.insert($0.start).inserted }
                .sorted { ($0.start.line, $0.start.character) < ($1.start.line, $1.start.character) }
            let matches = locs.map { l -> WorkspaceSearch.Match in
                let lineRange = index.range(ofLine: l.start.line + 1) ?? NSRange(location: 0, length: 0)
                let raw = lineRange.length > 0 ? ns.substring(with: lineRange) : ""
                let trimmed = raw.drop(while: { $0 == " " || $0 == "\t" })
                let lead = raw.utf16.count - String(trimmed).utf16.count
                let start = index.offset(of: l.start)
                var end = index.offset(of: l.end)
                if end <= start { end = start + identifierLength(ns, at: start) }
                let column = start - lineRange.location
                let length = max(0, min(end, NSMaxRange(lineRange)) - start)
                let highlight = NSRange(location: max(0, column - lead), length: length)
                return WorkspaceSearch.Match(line: l.start.line + 1, text: String(trimmed), range: NSRange(location: start, length: length),
                                             column: column + 1, highlight: highlight, matchedText: ns.substring(with: NSRange(location: start, length: length)))
            }
            return WorkspaceSearch.FileResult(path: path, matches: matches)
        }
    }

    static func identifierLength(_ ns: NSString, at offset: Int) -> Int {
        var end = offset
        while end < ns.length, let u = Unicode.Scalar(ns.character(at: end)),
              CharacterSet.alphanumerics.contains(u) || u == "_" { end += 1 }
        return end - offset
    }
}

extension WorkspaceSession {
    public func prepareRename(_ url: URL, at p: Position) async -> (start: Position, end: Position, placeholder: String?)? {
        guard let language else { return nil }
        return try? await language.client.prepareRename(url, at: p)
    }

    public func rename(_ url: URL, at p: Position, to newName: String) async -> WorkspaceEdit? {
        guard let language, let edit = try? await language.client.rename(url, at: p, to: newName), !edit.isEmpty else { return nil }
        return edit
    }

    public func references(_ url: URL, at p: Position) async -> [Location] {
        guard let language else { return [] }
        return (try? await language.client.references(url, at: p)) ?? []
    }

    public func declarationOrDefinition(_ url: URL, at p: Position) async -> Location? {
        guard let language else { return nil }
        if let d = (try? await language.client.declaration(url, at: p))?.first { return d }
        return (try? await language.client.definition(url, at: p))?.first
    }

    public func callers(_ url: URL, at p: Position) async -> (name: String, sites: [Location])? {
        guard let language, let item = (try? await language.client.prepareCallHierarchy(url, at: p))?.first else { return nil }
        let calls = (try? await language.client.incomingCalls(item)) ?? []
        let sites = calls.flatMap { c in
            (c.ranges.isEmpty ? [c.caller.selection] : c.ranges).map { Location(url: c.caller.url, start: $0, end: $0) }
        }
        return (item.name, sites)
    }
}

public enum DocumentSymbols {
    public static func enclosing(_ symbols: [SymbolScanner.Symbol], line: Int, text: NSString, index: LineIndex) -> SymbolScanner.Symbol? {
        var best: SymbolScanner.Symbol?
        var level = symbols
        while let s = level.last(where: { $0.line <= line }), line <= endLine(of: s, text: text, index: index) {
            best = s
            level = s.children
        }
        return best
    }

    public static func endLine(of s: SymbolScanner.Symbol, text ns: NSString, index: LineIndex) -> Int {
        guard let start = index.range(ofLine: s.line) else { return s.line }
        var depth = 0, opened = false, i = start.location
        let open = UInt16(UInt8(ascii: "{")), close = UInt16(UInt8(ascii: "}")), nl = UInt16(UInt8(ascii: "\n"))
        while i < ns.length {
            let c = ns.character(at: i)
            if c == open { depth += 1; opened = true }
            else if c == close { depth -= 1; if opened && depth == 0 { return index.line(at: i) } }
            else if c == nl && !opened && i > start.location + start.length { return s.line }
            i += 1
        }
        return opened ? index.line(at: max(0, ns.length - 1)) : s.line
    }

    public static func flattened(_ symbols: [SymbolScanner.Symbol], depth: Int = 0) -> [(depth: Int, symbol: SymbolScanner.Symbol)] {
        symbols.flatMap { [(depth, $0)] + flattened($0.children, depth: depth + 1) }
    }

    public static func badge(_ k: SymbolScanner.Symbol.Kind) -> String {
        switch k {
        case .class, .interface, .implementation: "C"
        case .struct: "S"
        case .enum, .enumCase: "E"
        case .protocol: "P"
        case .extension: "X"
        case .actor: "A"
        case .function: "F"
        case .typealias: "T"
        case .macro: "M"
        case .property: "V"
        case .initializer: "I"
        }
    }
}
