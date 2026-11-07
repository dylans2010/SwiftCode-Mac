import Foundation

public struct NavigationHistory: Equatable, Sendable {
    public private(set) var items: [String] = []
    public private(set) var index = -1

    public init() {}

    public var current: String? { index >= 0 ? items[index] : nil }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < items.count }

    public mutating func visit(_ path: String) {
        guard current != path else { return }
        items.removeSubrange((index + 1)...)
        items.append(path)
        index = items.count - 1
    }

    public mutating func back() -> String? {
        guard canGoBack else { return nil }
        index -= 1
        return items[index]
    }

    public mutating func forward() -> String? {
        guard canGoForward else { return nil }
        index += 1
        return items[index]
    }
}

public enum Counterparts {
    static let headerExtensions: Set<String> = ["h", "hpp", "hh"]
    static let implementationExtensions = ["m", "mm", "c", "cpp", "cc", "cxx"]

    public static func of(_ path: String, in files: [String], readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }) -> [String] {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent().path
        var out: [String] = []
        func add(_ candidates: [String]) {
            let sorted = candidates.sorted { a, b in
                let da = URL(fileURLWithPath: a).deletingLastPathComponent().path == dir
                let db = URL(fileURLWithPath: b).deletingLastPathComponent().path == dir
                return da != db ? da : a < b
            }
            for c in sorted where c != path && !out.contains(c) { out.append(c) }
        }
        func named(_ name: String, _ exts: [String]) -> [String] {
            files.filter {
                let u = URL(fileURLWithPath: $0)
                return u.deletingPathExtension().lastPathComponent == name && exts.contains(u.pathExtension.lowercased())
            }
        }
        if headerExtensions.contains(ext) {
            add(named(base, implementationExtensions))
        } else if implementationExtensions.contains(ext) {
            add(named(base, Array(headerExtensions)))
        }
        if ext == "swift" {
            if base.hasSuffix("Tests") { add(named(String(base.dropLast(5)), ["swift"])) } else { add(named(base + "Tests", ["swift"])) }
        }
        if ["storyboard", "xib"].contains(ext) {
            if let text = readFile(path) {
                for cls in customClasses(in: text) { add(named(cls, ["swift", "h", "m"])) }
            }
        } else if ["swift", "h", "m", "mm"].contains(ext) {
            let docs = files.filter { ["storyboard", "xib"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            add(docs.filter { readFile($0).map { customClasses(in: $0).contains(base) } ?? false })
        }
        return out
    }

    static func customClasses(in text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let r = rest.range(of: "customClass=\"") {
            let after = rest[r.upperBound...]
            guard let end = after.firstIndex(of: "\"") else { break }
            let name = String(after[..<end])
            if !out.contains(name) { out.append(name) }
            rest = after[end...]
        }
        return out
    }
}

extension Counterparts {
    public static func step(from current: String, ring: [String]?, forward: Bool, counterparts: () -> [String]) -> (next: String, ring: [String])? {
        let r = ring.flatMap { $0.contains(current) && $0.count > 1 ? $0 : nil } ?? ([current] + counterparts().filter { $0 != current })
        guard r.count > 1, let i = r.firstIndex(of: current) else { return nil }
        return (r[(i + (forward ? 1 : r.count - 1)) % r.count], r)
    }
}
