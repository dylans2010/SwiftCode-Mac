import Foundation

public enum GitBlame {
    public struct Commit: Equatable, Sendable {
        public var hash: String
        public var author: String
        public var authorEmail: String
        public var date: Date
        public var summary: String
        public var filename: String

        public var isUncommitted: Bool { hash.allSatisfy { $0 == "0" } }
        public var shortHash: String { String(hash.prefix(7)) }
    }

    public struct Block: Equatable, Sendable {
        public var firstLine: Int
        public var lineCount: Int
        public var commit: Commit
        public var lines: ClosedRange<Int> { firstLine...(firstLine + lineCount - 1) }
    }

    public static func parse(_ text: String) -> [Commit] {
        var commits: [String: Commit] = [:]
        var byLine: [Int: String] = [:]
        var current: String?
        var pending = Commit(hash: "", author: "", authorEmail: "", date: Date(timeIntervalSince1970: 0), summary: "", filename: "")
        var finalLine = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("\t") {
                if let h = current {
                    if commits[h] == nil { commits[h] = pending }
                    byLine[finalLine] = h
                }
                current = nil
                continue
            }
            if current == nil {
                let f = line.split(separator: " ")
                guard f.count >= 3, f[0].count >= 40, f[0].allSatisfy(\.isHexDigit), let n = Int(f[2]) else { continue }
                let h = String(f[0])
                current = h
                finalLine = n
                pending = commits[h] ?? Commit(hash: h, author: "", authorEmail: "", date: Date(timeIntervalSince1970: 0), summary: "", filename: "")
                continue
            }
            let (key, value): (Substring, String) = {
                guard let sp = line.firstIndex(of: " ") else { return (Substring(line), "") }
                return (line[..<sp], String(line[line.index(after: sp)...]))
            }()
            switch key {
            case "author": pending.author = value
            case "author-mail": pending.authorEmail = value.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            case "author-time": pending.date = Date(timeIntervalSince1970: TimeInterval(value) ?? 0)
            case "summary": pending.summary = value
            case "filename": pending.filename = value
            default: break
            }
        }
        guard let last = byLine.keys.max() else { return [] }
        return (1...last).compactMap { byLine[$0].flatMap { commits[$0] } }
    }

    public static func blocks(_ perLine: [Commit]) -> [Block] {
        var out: [Block] = []
        for (i, c) in perLine.enumerated() {
            if let last = out.last, last.commit.hash == c.hash, last.firstLine + last.lineCount == i + 1 {
                out[out.count - 1].lineCount += 1
            } else {
                out.append(Block(firstLine: i + 1, lineCount: 1, commit: c))
            }
        }
        return out
    }

    private static let absoluteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public static func annotation(_ c: Commit, now: Date = Date(), calendar: Calendar = .current) -> String {
        if c.isUncommitted { return "Not Committed Yet" }
        let datePart: String
        switch GitBlameSettings.dateFormat {
        case .relative:
            datePart = GitDates.relativeDay(c.date, now: now, calendar: calendar)
        case .absolute:
            datePart = absoluteDateFormatter.string(from: c.date)
        case .shortHash:
            datePart = c.shortHash
        }
        return "\(c.author)  \(datePart)"
    }

    public static func details(_ c: Commit, calendar: Calendar = .current) -> String {
        if c.isUncommitted { return "Not Committed Yet\nLocal changes not yet committed." }
        return "\(c.shortHash) \u{2014} \(c.author) <\(c.authorEmail)>\n\(GitDates.detail(c.date, calendar: calendar))\n\n\(c.summary)"
    }
}

extension GitRepository {
    public func blame(of path: String, contents: String? = nil) -> [GitBlame.Commit]? {
        guard let rel = relative(path) else { return nil }
        var args = ["blame", "--porcelain"]
        var temp: URL?
        if let contents {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-blame-\(UUID().uuidString)")
            guard (try? contents.write(to: u, atomically: true, encoding: .utf8)) != nil else { return nil }
            temp = u
            args += ["--contents", u.path]
        }
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
        guard headHash() != nil, let out = try? git(args + ["--", rel]) else { return nil }
        return GitBlame.parse(out)
    }
}
