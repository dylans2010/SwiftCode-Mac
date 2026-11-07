import Foundation
import YcodeSubprocess

extension GitRepository {
    public struct Commit: Equatable, Sendable {
        public var hash: String
        public var authorName: String
        public var authorEmail: String
        public var date: Date
        public var subject: String
        public var body: String
        public var branches: [String]
        public var tags: [String]
        public var signature: String

        public var shortHash: String { String(hash.prefix(7)) }
        public var message: String { body.isEmpty ? subject : subject + "\n\n" + body }
        public var verification: String { signature == "G" ? "Commit verified" : "Commit unverified" }
    }

    public struct Change: Equatable, Sendable {
        public var path: String
        public var index: Character
        public var worktree: Character
        public var status: FileStatus
        public var isStaged: Bool { index != " " && index != "?" }
        public var isUnstaged: Bool { worktree != " " }
    }

    public struct Author: Equatable, Sendable {
        public var name: String
        public var email: String
    }

    public func currentBranch() -> String? {
        let s = (try? git(["symbolic-ref", "--quiet", "--short", "HEAD"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return s?.isEmpty == false ? s : nil
    }

    public func headHash() -> String? {
        let s = (try? git(["rev-parse", "--verify", "--quiet", "HEAD"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return s?.isEmpty == false ? s : nil
    }

    public func config(_ key: String) -> String? {
        let s = (try? git(["config", "--get", key]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return s?.isEmpty == false ? s : nil
    }

    public func author() -> Author { Author(name: config("user.name") ?? "", email: config("user.email") ?? "") }

    public func changes() throws -> [Change] {
        var out: [Change] = []
        let entries = try git(["status", "--porcelain=v1", "-z", "--untracked-files=all"]).split(separator: "\0", omittingEmptySubsequences: true)
        let flat = try status()
        var i = 0
        while i < entries.count {
            let e = String(entries[i])
            i += 1
            guard e.count > 3 else { continue }
            let x = e[e.startIndex], y = e[e.index(after: e.startIndex)]
            if x == "R" || x == "C" { i += 1 }
            let path = root.appendingPathComponent(String(e.dropFirst(3))).path
            out.append(Change(path: path, index: x, worktree: y, status: flat[path] ?? .modified))
        }
        return out.sorted { $0.path < $1.path }
    }

    public func stashes() -> [String] {
        ((try? git(["stash", "list", "--format=%gd: %gs"])) ?? "").split(separator: "\n").map(String.init)
    }

    public func recentBranches(limit: Int = 5) -> [String] {
        let log = (try? git(["reflog", "show", "--format=%gs", "-n", "200", "HEAD"])) ?? ""
        let existing = Set(((try? branches()) ?? []).map(\.name))
        let current = currentBranch()
        var out: [String] = []
        for line in log.split(separator: "\n") where line.hasPrefix("checkout: moving from ") {
            let parts = line.dropFirst("checkout: moving from ".count).components(separatedBy: " to ")
            for name in parts.reversed() where existing.contains(name) && name != current && !out.contains(name) { out.append(name) }
            if out.count >= limit { break }
        }
        return Array(out.prefix(limit))
    }

    static let fieldSeparator = "\u{1f}", recordSeparator = "\u{1e}"

    public func log(_ ref: String = "HEAD", since: Date? = nil, limit: Int = 500) -> [Commit] {
        var args = ["log", "--format=%H%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%G?%x1f%s%x1f%b%x1e", "-n", String(limit)]
        if let since { args.append("--since=@\(Int(since.timeIntervalSince1970))") }
        args += [ref, "--"]
        guard let text = try? git(args) else { return [] }
        return text.components(separatedBy: Self.recordSeparator).compactMap(Self.parseCommit)
    }

    public func commit(_ hash: String) -> Commit? { log(hash, limit: 1).first }

    public func history(ofFile path: String, limit: Int = 200) -> [Commit] {
        guard let rel = relative(path) else { return [] }
        let args = ["log", "--follow", "--format=%H%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%G?%x1f%s%x1f%b%x1e", "-n", String(limit), "--", rel]
        guard let text = try? git(args) else { return [] }
        return text.components(separatedBy: Self.recordSeparator).compactMap(Self.parseCommit)
    }

    static func parseCommit(_ record: String) -> Commit? {
        let f = record.trimmingCharacters(in: .newlines).components(separatedBy: fieldSeparator)
        guard f.count >= 8, f[0].count >= 7 else { return nil }
        var branches: [String] = [], tags: [String] = []
        for d in f[4].components(separatedBy: ", ") where !d.isEmpty {
            if d.hasPrefix("tag: ") { tags.append(String(d.dropFirst(5))) }
            else if d.hasPrefix("HEAD -> ") { branches.append(String(d.dropFirst(8))) }
            else if d != "HEAD" { branches.append(d) }
        }
        return Commit(hash: f[0], authorName: f[1], authorEmail: f[2], date: Date(timeIntervalSince1970: TimeInterval(f[3]) ?? 0),
                      subject: f[6], body: f[7].trimmingCharacters(in: .whitespacesAndNewlines), branches: branches, tags: tags,
                      signature: f[5].isEmpty ? "N" : f[5])
    }

    public func files(in hash: String) -> [(path: String, status: FileStatus)] {
        let text = (try? git(["diff-tree", "--no-commit-id", "--name-status", "-r", "--root", "-M", hash])) ?? ""
        return text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t").map(String.init)
            guard f.count >= 2, let c = f[0].first else { return nil }
            let status: FileStatus = switch c {
            case "A": .added
            case "D": .deleted
            case "R": .renamed
            default: .modified
            }
            return (f[f.count - 1], status)
        }
    }

    public func branches(containing hash: String) -> [String] {
        ((try? git(["branch", "--format=%(refname:short)", "--contains", hash])) ?? "").split(separator: "\n").map(String.init)
    }

    public func upstream(of branch: String) -> String? {
        let s = (try? git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", branch + "@{upstream}"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s?.isEmpty == false ? s : nil
    }

    public func remote(of branch: String) -> String? { config("branch.\(branch).remote") }

    public enum DiffScope: Int, Sendable { case all, unstaged, staged }

    public func diff(of path: String, scope: DiffScope) -> String {
        let rel = repoRelative(path)
        let untracked = (try? git(["ls-files", "--error-unmatch", "--", rel])) == nil
        if untracked {
            guard scope != .staged else { return "" }
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let lines = LineDiff.lines(text)
            return "@@ -0,0 +1,\(lines.count) @@\n" + lines.map { "+" + $0 }.joined(separator: "\n")
        }
        let args: [String] = switch scope {
        case .all: headHash() == nil ? ["diff", "--cached"] : ["diff", "HEAD"]
        case .unstaged: ["diff"]
        case .staged: ["diff", "--cached"]
        }
        let text = (try? git(args + ["--no-color", "--no-ext-diff", "-U3", "--", rel])) ?? ""
        guard let hunk = text.range(of: "\n@@") else { return text.hasPrefix("@@") ? text : "" }
        return String(text[text.index(after: hunk.lowerBound)...])
    }

    func repoRelative(_ path: String) -> String {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return p.hasPrefix(root.path + "/") ? String(p.dropFirst(root.path.count + 1)) : path
    }

    public func stage(_ paths: [String]) throws { guard !paths.isEmpty else { return }; _ = try git(["add", "--"] + paths.map(repoRelative)) }
    public func stageAll() throws { _ = try git(["add", "-A"]) }

    public func unstage(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        if headHash() == nil { _ = try git(["rm", "--cached", "-q", "--"] + paths.map(repoRelative)) }
        else { _ = try git(["reset", "-q", "HEAD", "--"] + paths.map(repoRelative)) }
    }

    public func unstageAll() throws {
        if headHash() == nil { _ = try git(["rm", "-r", "--cached", "-q", "."]) } else { _ = try git(["reset", "-q"]) }
    }

    public func discard(_ path: String) throws {
        let rel = repoRelative(path)
        if (try? git(["ls-files", "--error-unmatch", "--", rel])) == nil {
            try Trash.move(URL(fileURLWithPath: path))
        } else if headHash() != nil, (try? git(["cat-file", "-e", "HEAD:" + rel])) != nil {
            _ = try git(["checkout", "HEAD", "--", rel])
        } else {
            _ = try git(["rm", "--cached", "-q", "--", rel])
            if FileManager.default.fileExists(atPath: path) {
                try Trash.move(URL(fileURLWithPath: path))
            }
        }
    }

    @discardableResult
    public func commitStaged(message: String, amend: Bool = false) throws -> String {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw GitError(description: "empty commit message") }
        _ = try git(["commit", "-q", "-m", message] + (amend ? ["--amend"] : []))
        return try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func markResolved(_ paths: [String]) throws { try stage(paths) }

    public func stash(message: String) throws {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try git(["stash", "push", "--include-untracked"] + (m.isEmpty ? [] : ["-m", m]))
    }

    public func cherryPick(_ hash: String) throws { _ = try git(["cherry-pick", hash]) }

    public func switchBranch(_ name: String) throws {
        if (try? status())?.values.contains(.conflicted) == true {
            throw GitError(description: "The working copy has unresolved conflicts. Resolve them before switching branches.")
        }
        _ = try git(["switch", "--", name])
    }
    public func fetch() throws { _ = try git(["fetch", "--all", "--prune"]) }
    public func pull() throws { _ = try git(["pull", "--ff-only"]) }
    public func push() throws { _ = try git(["push"]) }

    public static func initialize(at dir: URL, git: String = HostTool.path("git")) throws -> GitRepository? {
        _ = try run(git, ["-C", dir.path, "init", "-q"])
        return GitRepository(containing: dir, git: git)
    }

    public static func cloneFolderName(for address: String) -> String {
        let trimmed = address.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/")))
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        let name = last.hasSuffix(".git") ? String(last.dropLast(4)) : last
        return name.isEmpty ? "Repository" : name
    }

    public static func clone(_ url: String, into dir: URL, git: String = HostTool.path("git")) throws {
        _ = try run(git, ["clone", "--", url, dir.path])
    }
}

public enum GitDates {
    public static func relativeDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    public static func detail(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f.string(from: date)
    }
}

public enum HistoryScope: Int, CaseIterable, Sendable {
    case all, day, week, month
    public static let titles = ["All", "Last 24 Hours", "Last 7 Days", "Last 30 Days"]
    public func since(now: Date = Date()) -> Date? {
        switch self {
        case .all: nil
        case .day: now.addingTimeInterval(-86_400)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-30 * 86_400)
        }
    }

    public func apply(_ commits: [GitRepository.Commit], filter: String, now: Date = Date()) -> [GitRepository.Commit] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let since = since(now: now)
        return commits.filter { c in
            (since.map { c.date >= $0 } ?? true)
                && (q.isEmpty || c.subject.lowercased().contains(q) || c.authorName.lowercased().contains(q)
                    || c.message.lowercased().contains(q) || c.hash.hasPrefix(q))
        }
    }
}
