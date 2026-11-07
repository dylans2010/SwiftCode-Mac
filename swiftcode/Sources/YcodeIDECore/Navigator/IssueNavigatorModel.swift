import Foundation
import YcodeBuild

public struct IssueNavigatorModel: Equatable {
    public struct Entry: Equatable, Hashable {
        public var diagnostic: Diagnostic
        public var isStale: Bool
        public init(_ diagnostic: Diagnostic, stale: Bool = false) { self.diagnostic = diagnostic; isStale = stale }
    }

    public enum Token: Hashable {
        case kind(String)
        case notDeprecation
        public var title: String {
            switch self {
            case .kind(let k): "Kind = \(k)"
            case .notDeprecation: "≠ Deprecation"
            }
        }
    }

    public static let menuSections: [(String, [String])] = [
        ("Additional Filtering", ["Deprecation"]),
        ("Add Filter", [Token.kind("Build").title, Token.notDeprecation.title]),
        ("", ["Clear Recents"]),
    ]

    public private(set) var stale: [Diagnostic] = []
    private var lastBuild: [Diagnostic] = []
    public var tokens: [Token] = []
    public var recentTokens: [Token] = []
    public var deprecationOnly = false
    public var errorsOnly = false

    public init() {}

    public private(set) var isBuilding = false

    public mutating func startBuild() { isBuilding = true }

    public mutating func finishBuild(_ current: [Diagnostic], full: Bool, compiledFiles: Set<String>? = nil) {
        isBuilding = false
        let now = Set(current.map(IssueMerge.key))
        if full { stale = [] } else {
            var next: [Diagnostic] = []
            var kept = Set<IssueMerge.Key>()
            for d in stale + lastBuild where !now.contains(IssueMerge.key(d)) && kept.insert(IssueMerge.key(d)).inserted {
                guard let file = d.location?.file, let compiled = compiledFiles else { continue }
                if !compiled.contains(URL(fileURLWithPath: file).lastPathComponent) { next.append(d) }
            }
            stale = next
        }
        lastBuild = current
    }

    public static func compiledFiles(inLog log: [String], isPackage: Bool) -> Set<String>? {
        let sources: Set<String> = ["swift", "c", "m", "mm", "cpp", "cc", "cxx", "s"]
        var out = Set<String>()
        var sawTask = false
        for line in log {
            guard let (_, group, _, _) = BuildLogModel.task(line, isPackage: isPackage) else { continue }
            sawTask = true
            let s = line.trimmingCharacters(in: .whitespaces)
            if let r = s.range(of: " (in target '") {
                let words = s[..<r.lowerBound].split(separator: " ")
                guard let cmd = words.first, ["CompileSwift", "SwiftCompile", "CompileC"].contains(String(cmd)) else { continue }
                for w in words.dropFirst() {
                    let name = URL(fileURLWithPath: String(w)).lastPathComponent
                    if sources.contains(URL(fileURLWithPath: name).pathExtension) { out.insert(name) }
                }
            } else if group.hasPrefix("Compiling ") {
                for name in group.dropFirst("Compiling ".count).split(separator: " ") { out.insert(String(name)) }
            }
        }
        return sawTask ? out : nil
    }

    public mutating func addToken(_ t: Token) {
        if !tokens.contains(t) { tokens.append(t) }
        recentTokens.removeAll { $0 == t }
        recentTokens.insert(t, at: 0)
    }
    public mutating func clearRecents() { recentTokens = [] }

    public static func isDeprecation(_ d: Diagnostic) -> Bool {
        let m = d.message.lowercased()
        return m.contains("deprecated") || m.contains("deprecation")
    }

    public func entries(fresh: [Diagnostic], text: String = "", keepFile: (String) -> Bool = { _ in true }) -> [Entry] {
        var shown = Set(fresh.map(IssueMerge.key))
        var shownStale: [Diagnostic] = []
        for d in stale + (isBuilding ? lastBuild : []) where shown.insert(IssueMerge.key(d)).inserted { shownStale.append(d) }
        let all = fresh.map { Entry($0) } + shownStale.map { Entry($0, stale: true) }
        let t = text.lowercased()
        return all.filter { e in
            let d = e.diagnostic
            if d.severity == .note { return false }
            if errorsOnly && d.severity != .error { return false }
            if deprecationOnly && !Self.isDeprecation(d) { return false }
            if tokens.contains(.notDeprecation) && Self.isDeprecation(d) { return false }
            for case .kind(let k) in tokens where k != "Build" { return false }
            if let f = d.location?.file, !keepFile(f) { return false }
            if !t.isEmpty && !d.message.lowercased().contains(t) { return false }
            return true
        }
    }

    public func capsuleCounts(fresh: [Diagnostic]) -> (errors: Int, warnings: Int) {
        var shown = Set(fresh.map(IssueMerge.key))
        var all = fresh
        for d in stale + (isBuilding ? lastBuild : []) where shown.insert(IssueMerge.key(d)).inserted { all.append(d) }
        return (all.filter { $0.severity == .error }.count, all.filter { $0.severity == .warning }.count)
    }
}

public enum IssueMerge {
    public static func capitalized(_ message: String) -> String {
        guard let first = message.first, first.isLowercase else { return message }
        return first.uppercased() + message.dropFirst()
    }

    public static func capitalized(_ d: Diagnostic) -> Diagnostic {
        var d = d
        d.message = capitalized(d.message)
        d.notes = d.notes.map(capitalized)
        return d
    }

    public static func canonicalPath(_ path: String) -> String {
        var p = URL(fileURLWithPath: path).standardizedFileURL.path
        for dir in ["/private/var/", "/private/tmp/", "/private/etc/"] where p.hasPrefix(dir) { p.removeFirst("/private".count) }
        return p
    }

    public struct Key: Hashable {
        public var file: String?
        public var line: Int?
        public var severity: Diagnostic.Severity
        public var message: String
    }

    public static func key(_ d: Diagnostic) -> Key {
        Key(file: d.location.map { canonicalPath($0.file) }, line: d.location?.line, severity: d.severity, message: capitalized(d.message))
    }

    public static func merge(_ sources: [[Diagnostic]], live: [Diagnostic], liveHiddenFiles: Set<String> = []) -> [Diagnostic] {
        var out: [Diagnostic] = []
        var index: [Key: Int] = [:]
        for d in sources.joined() {
            let k = key(d)
            guard index[k] == nil else { continue }
            index[k] = out.count
            out.append(capitalized(d))
        }
        for d in live {
            if let f = d.location?.file, liveHiddenFiles.contains(canonicalPath(f)) { continue }
            let k = key(d)
            if let i = index[k] {
                if out[i].fixIts.isEmpty && !d.fixIts.isEmpty { out[i].fixIts = d.fixIts }
                continue
            }
            index[k] = out.count
            out.append(capitalized(d))
        }
        return out
    }
}

public struct IssueGrouping {
    public var projectName: String
    public var targetOrder: [String]
    public var targetsOfFile: (String) -> [String]
    public init(projectName: String, targetOrder: [String] = [], targetsOfFile: @escaping (String) -> [String] = { _ in [] }) {
        self.projectName = projectName
        self.targetOrder = targetOrder
        self.targetsOfFile = targetsOfFile
    }
}

extension IssueNavigatorModel {
    public struct FileRow: Equatable {
        public var file: String
        public var title: String
        public var entries: [Entry]
    }

    public struct GroupRow: Equatable {
        public enum Kind: Equatable { case project, target }
        public var kind: Kind
        public var title: String
        public var entries: [Entry]
        public var files: [FileRow]
        public var count: Int { entries.count + files.reduce(0) { $0 + $1.entries.count } }
        public var countText: String { "\(count) issue\(count == 1 ? "" : "s")" }
    }

    public static func tree(_ entries: [Entry], grouping: IssueGrouping) -> [GroupRow] {
        var projectEntries: [Entry] = []
        var byGroup: [String?: [String: [Entry]]] = [:]
        var targetsCache: [String: [String]] = [:]
        for e in entries {
            guard let file = e.diagnostic.location?.file, !file.isEmpty else { projectEntries.append(e); continue }
            let key = IssueMerge.canonicalPath(file)
            let targets = targetsCache[key] ?? grouping.targetsOfFile(file)
            targetsCache[key] = targets
            for t in targets.isEmpty ? [nil] : targets.map(Optional.some) {
                byGroup[t, default: [:]][file, default: []].append(e)
            }
        }
        func fileRows(_ files: [String: [Entry]]) -> [FileRow] {
            files.map { file, list in
                let sorted = list.enumerated().sorted { a, b in
                    let la = a.element.diagnostic.location?.line ?? 0, lb = b.element.diagnostic.location?.line ?? 0
                    return la != lb ? la < lb : a.offset < b.offset
                }.map(\.element)
                return FileRow(file: file, title: URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent, entries: sorted)
            }.sorted { a, b in
                let c = a.title.localizedStandardCompare(b.title)
                return c != .orderedSame ? c == .orderedAscending : a.file < b.file
            }
        }
        var rows: [GroupRow] = []
        let projectFiles = byGroup[nil] ?? [:]
        if !projectEntries.isEmpty || !projectFiles.isEmpty {
            rows.append(GroupRow(kind: .project, title: grouping.projectName, entries: projectEntries, files: fileRows(projectFiles)))
        }
        let named = byGroup.keys.compactMap { $0 }
        let ordered = grouping.targetOrder.filter(named.contains)
            + named.filter { !grouping.targetOrder.contains($0) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var seen = Set<String>()
        for t in ordered where seen.insert(t).inserted {
            rows.append(GroupRow(kind: .target, title: t, entries: [], files: fileRows(byGroup[t] ?? [:])))
        }
        return rows
    }
}
