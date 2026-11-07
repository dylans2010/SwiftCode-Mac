import Foundation

public struct FindNavigatorModel: Equatable, Sendable {
    public enum Mode: Int, Sendable { case find, replace }

    public var mode: Mode = .find
    public var query = FindQuery("")
    public var replacement = ""
    public var scope: FindScope = .workspace
    public private(set) var results: [WorkspaceSearch.FileResult] = []
    public private(set) var summary = FindEngine.Summary()
    public var plan: ReplacePlan?
    public private(set) var recent: [String] = []
    public static let maxRecent = 10
    public private(set) var cursor: (file: Int, match: Int)?

    public init() {}

    public static func == (a: Self, b: Self) -> Bool {
        a.mode == b.mode && a.query == b.query && a.replacement == b.replacement && a.scope == b.scope && a.results == b.results
            && a.summary == b.summary && a.plan == b.plan && a.recent == b.recent && a.cursor?.file == b.cursor?.file && a.cursor?.match == b.cursor?.match
    }

    public mutating func noteRecent(_ q: String) {
        guard !q.isEmpty else { return }
        recent = Array(([q] + recent.filter { $0 != q }).prefix(Self.maxRecent))
    }

    public mutating func clearRecent() { recent = [] }

    public mutating func begin() {
        results = []
        summary = FindEngine.Summary()
        cursor = nil
        plan = nil
    }

    public mutating func append(_ file: WorkspaceSearch.FileResult) {
        results.append(file)
        summary.matchCount += file.matches.count
    }

    public mutating func finish(_ s: FindEngine.Summary) {
        results = s.files
        summary = s
        cursor = nil
        plan = mode == .replace && query.kind.supportsReplace ? ReplacePlan(query: query, replacement: replacement, results: results) : nil
    }

    public mutating func setReplacement(_ r: String) {
        replacement = r
        plan?.replacement = r
    }

    public mutating func setMode(_ m: Mode) {
        mode = m
        plan = m == .replace && query.kind.supportsReplace ? (plan ?? ReplacePlan(query: query, replacement: replacement, results: results)) : nil
    }

    public var matchCount: Int { results.reduce(0) { $0 + $1.matches.count } }

    public var countText: String {
        guard !query.text.isEmpty else { return "" }
        let n = matchCount, f = results.count
        if n == 0 { return "No results" }
        var s = "\(n) result\(n == 1 ? "" : "s") in \(f) file\(f == 1 ? "" : "s")"
        if summary.truncated { s += " (stopped at the limit)" }
        return s
    }

    @discardableResult
    public mutating func step(forward: Bool) -> (path: String, match: WorkspaceSearch.Match)? {
        let flat = results.enumerated().flatMap { f in f.element.matches.indices.map { (f.offset, $0) } }
        guard !flat.isEmpty else { return nil }
        var i: Int
        if let c = cursor, let at = flat.firstIndex(where: { $0.0 == c.file && $0.1 == c.match }) {
            i = (at + (forward ? 1 : -1) + flat.count) % flat.count
        } else {
            i = forward ? 0 : flat.count - 1
        }
        cursor = (flat[i].0, flat[i].1)
        let f = results[flat[i].0]
        return (f.path, f.matches[flat[i].1])
    }

    public mutating func select(file: Int, match: Int) {
        guard results.indices.contains(file), results[file].matches.indices.contains(match) else { return }
        cursor = (file, match)
    }
}
