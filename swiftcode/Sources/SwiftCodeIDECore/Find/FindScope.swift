import Foundation

public enum FindScope: Equatable, Hashable, Sendable {
    case workspace
    case project(String)
    case group(String)
    case openFiles
    case currentResults
    case custom(String)
}

public struct FindCandidate: Equatable, Hashable, Sendable {
    public var path: String
    public var inFolder: Bool
    public init(_ path: String, inFolder: Bool = false) {
        self.path = path
        self.inFolder = inFolder
    }
}

public struct CustomFindScope: Codable, Equatable, Hashable, Sendable {
    public enum Field: String, Codable, CaseIterable, Sendable {
        case name, path, `extension`, location
        public var title: String {
            switch self {
            case .name: "Name"
            case .path: "Path"
            case .extension: "Extension"
            case .location: "Location"
            }
        }
    }

    public enum Operator: String, Codable, CaseIterable, Sendable {
        case contains, `is`, isNot, startsWith, endsWith, matches
        public var title: String {
            switch self {
            case .contains: "contains"
            case .is: "is"
            case .isNot: "is not"
            case .startsWith: "starts with"
            case .endsWith: "ends with"
            case .matches: "matches regular expression"
            }
        }
    }

    public struct Rule: Codable, Equatable, Hashable, Sendable {
        public var field: Field
        public var op: Operator
        public var value: String
        public init(_ field: Field, _ op: Operator, _ value: String) {
            self.field = field
            self.op = op
            self.value = value
        }
    }

    public static let openFilesValue = "Open Files"

    public var name: String
    public var matchAll: Bool
    public var rules: [Rule]

    public init(name: String, matchAll: Bool = true, rules: [Rule]) {
        self.name = name
        self.matchAll = matchAll
        self.rules = rules
    }

    public func includes(_ path: String, isOpen: Bool) -> Bool {
        guard !rules.isEmpty else { return false }
        let results = rules.lazy.map { Self.holds($0, path: path, isOpen: isOpen) }
        return matchAll ? results.allSatisfy { $0 } : results.contains(true)
    }

    static func holds(_ r: Rule, path: String, isOpen: Bool) -> Bool {
        if r.field == .location {
            let inside = r.value == openFilesValue ? isOpen : (path == r.value || path.hasPrefix(r.value.hasSuffix("/") ? r.value : r.value + "/"))
            return r.op == .isNot ? !inside : inside
        }
        let subject: String
        switch r.field {
        case .name: subject = (path as NSString).lastPathComponent
        case .extension: subject = (path as NSString).pathExtension
        default: subject = path
        }
        let s = subject.lowercased(), v = r.value.lowercased()
        switch r.op {
        case .contains: return s.contains(v)
        case .is: return s == v
        case .isNot: return s != v
        case .startsWith: return s.hasPrefix(v)
        case .endsWith: return s.hasSuffix(v)
        case .matches:
            guard let re = try? NSRegularExpression(pattern: r.value, options: [.caseInsensitive]) else { return false }
            return re.firstMatch(in: subject, range: NSRange(location: 0, length: (subject as NSString).length)) != nil
        }
    }
}

public struct FindScopeResolver: Sendable {
    public var root: NavigatorNode
    public var openFiles: [String]
    public var currentResults: [String]
    public var customScopes: [CustomFindScope]
    public var ignore: FindIgnoreRules

    public static let opaqueBundles: Set<String> = [
        "xcassets", "xcodeproj", "xcworkspace", "xcdatamodeld", "xcdatamodel", "bundle", "framework", "xcframework", "app", "appex",
        "xctest", "dSYM", "car", "icon", "rcproject", "reality", "scnassets", "xcarchive", "xcresult",
    ]

    public init(root: NavigatorNode, openFiles: [String] = [], currentResults: [String] = [], customScopes: [CustomFindScope] = [],
                ignore: FindIgnoreRules = FindIgnoreRules()) {
        self.root = root
        self.openFiles = openFiles
        self.currentResults = currentResults
        self.customScopes = customScopes
        self.ignore = ignore
    }

    public func candidates(for scope: FindScope) -> [FindCandidate] {
        switch scope {
        case .workspace:
            return collect(root)
        case .project(let path), .group(let path):
            if let node = root.find(path: path) { return collect(node) }
            return collect(root).filter { $0.path == path || $0.path.hasPrefix(path + "/") }
        case .openFiles:
            return unique(openFiles.map { FindCandidate($0) })
        case .currentResults:
            return unique(currentResults.map { FindCandidate($0) })
        case .custom(let name):
            guard let s = customScopes.first(where: { $0.name == name }) else { return [] }
            let open = Set(openFiles)
            return unique((collect(root) + openFiles.map { FindCandidate($0) }).filter { s.includes($0.path, isOpen: open.contains($0.path)) })
        }
    }

    public func collect(_ node: NavigatorNode) -> [FindCandidate] {
        var out: [FindCandidate] = []
        var seen = Set<String>()
        func add(_ c: FindCandidate) { if seen.insert(c.path).inserted { out.append(c) } }
        func walk(_ n: NavigatorNode, inFolder: Bool) {
            switch n.kind {
            case .file:
                guard let p = n.path else { return }
                if inFolder && ignore.isIgnored(p) { return }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                    guard !Self.opaqueBundles.contains((p as NSString).pathExtension) else { return }
                    listDirectory(p, into: add)
                } else {
                    add(FindCandidate(p, inFolder: inFolder))
                }
            case .folder:
                if inFolder, let p = n.path, ignore.isIgnored(p, isDirectory: true) { return }
                for c in n.children { walk(c, inFolder: true) }
            case .group:
                for c in n.children { walk(c, inFolder: inFolder) }
            case .container:
                let package = NavigatorTree.isPackageRoot(n)
                for c in n.children { walk(c, inFolder: inFolder || package) }
            }
        }
        walk(node, inFolder: false)
        return out
    }

    func listDirectory(_ dir: String, into add: (FindCandidate) -> Void) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for name in names.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) where !name.hasPrefix(".") {
            let full = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard !Self.opaqueBundles.contains((name as NSString).pathExtension), !ignore.isIgnored(full, isDirectory: true) else { continue }
                listDirectory(full, into: add)
            } else if !ignore.isIgnored(full) {
                add(FindCandidate(full, inFolder: true))
            }
        }
    }

    private func unique(_ list: [FindCandidate]) -> [FindCandidate] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.path).inserted }
    }
}
