import Foundation

extension GitRepository {
    public struct CommitSummary: Equatable, Sendable {
        public var hash: String
        public var shortHash: String
        public var author: String
        public var date: String
        public var subject: String
    }

    package func relative(_ path: String) -> String? {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        guard p.hasPrefix(root.path + "/") else { return nil }
        return String(p.dropFirst(root.path.count + 1))
    }

    public func contents(of path: String, at revision: String?) -> String? {
        guard let rel = relative(path) else { return nil }
        return try? git(["show", (revision ?? "") + ":" + rel])
    }

    public func recentCommits(limit: Int = 50, path: String? = nil) -> [CommitSummary] {
        var args = ["log", "-n", "\(limit)", "--date=short", "--format=%H%x1f%h%x1f%an%x1f%ad%x1f%s"]
        if let path, let rel = relative(path) { args += ["--", rel] }
        guard let out = try? git(args) else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 5 else { return nil }
            return CommitSummary(hash: f[0], shortHash: f[1], author: f[2], date: f[3], subject: f[4])
        }
    }
}
