import Foundation
import SwiftCodeSubprocess

public struct GitRepository: Sendable {
    public struct Ref: Equatable, Sendable {
        public var name: String
        public var isCurrent: Bool
    }

    public struct Remote: Equatable, Sendable {
        public var name: String
        public var url: String
    }

    public enum FileStatus: String, Equatable, Sendable {
        case modified = "M", added = "A", deleted = "D", renamed = "R", untracked = "?", conflicted = "C"
    }

    public struct GitError: LocalizedError, CustomStringConvertible {
        public var description: String
        public var errorDescription: String? {
            let lines = description.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("Cloning into ") }
            return lines.map { $0.hasPrefix("fatal: ") ? String($0.dropFirst(7)) : $0 }.joined(separator: "\n")
        }
        package init(description: String) { self.description = description }
    }

    public let root: URL
    public var git: String = HostTool.path("git")

    public init?(containing path: URL, git: String = HostTool.path("git")) {
        self.git = git
        let dir = (try? path.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? path : path.deletingLastPathComponent()
        guard let top = try? Self.run(git, ["-C", dir.path, "rev-parse", "--show-toplevel"]).trimmingCharacters(in: .whitespacesAndNewlines),
              !top.isEmpty else { return nil }
        root = URL(fileURLWithPath: top).standardizedFileURL
    }

    static func run(_ git: String, _ args: [String]) throws -> String {
        let r = try runStatus(git, args)
        guard r.status == 0 else { throw GitError(description: r.stderrText) }
        return r.stdoutText
    }

    static func runStatus(_ git: String, _ args: [String]) throws -> Subprocess.Output {
        try Subprocess.run(git, args, environment: environment)
    }

    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        for k in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
                  "GIT_COMMON_DIR", "GIT_NAMESPACE", "GIT_PREFIX", "GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM",
                  "SSH_ASKPASS", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT"] {
            env[k] = nil
        }
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_PAGER"] = "cat"
        env["GIT_EDITOR"] = "true"
        env["GIT_SEQUENCE_EDITOR"] = "true"
        env["GIT_MERGE_AUTOEDIT"] = "no"
        env["GIT_ASKPASS"] = "true"
        env["SSH_ASKPASS_REQUIRE"] = "never"
        env["GCM_INTERACTIVE"] = "never"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        if IDEProcess.isTestProcess, let global = testConfiguration {
            env["GIT_CONFIG_NOSYSTEM"] = "1"
            env["GIT_CONFIG_GLOBAL"] = global
        }
        return env
    }()

    static let testConfiguration: String? = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-git-test-config-\(ProcessInfo.processInfo.processIdentifier)")
        let hooks = dir.appendingPathComponent("hooks")
        let file = dir.appendingPathComponent("gitconfig")
        let text = """
        [user]
        \tname = SwiftCode Test
        \temail = test@swiftcode.invalid
        [commit]
        \tgpgsign = false
        [tag]
        \tgpgsign = false
        \tforceSignAnnotated = false
        [init]
        \tdefaultBranch = main
        [merge]
        \tconflictstyle = merge
        [rerere]
        \tenabled = false
        [pull]
        \trebase = false
        [core]
        \thooksPath = \(hooks.path)
        \tautocrlf = false

        """
        do {
            try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            return file.path
        } catch { return nil }
    }()

    func gitStatus(_ args: [String]) throws -> Subprocess.Output { try Self.runStatus(git, ["-C", root.path] + args) }

    func git(_ args: [String]) throws -> String { try Self.run(git, ["-C", root.path] + args) }

    public func branches() throws -> [Ref] { try refs("refs/heads") }
    public func tags() throws -> [Ref] { try refs("refs/tags") }
    public func remoteBranches() throws -> [Ref] { try refs("refs/remotes").filter { !$0.name.hasSuffix("/HEAD") } }

    func refs(_ prefix: String) throws -> [Ref] {
        try git(["for-each-ref", "--format=%(HEAD)%09%(refname)", prefix])
            .split(separator: "\n").map { line in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                var name = parts.count > 1 ? parts[1] : parts[0]
                if name.hasPrefix(prefix + "/") { name = String(name.dropFirst(prefix.count + 1)) }
                return Ref(name: name, isCurrent: parts.first == "*")
            }
    }

    public func remotes() throws -> [Remote] {
        var seen = Set<String>()
        return try git(["remote", "-v"]).split(separator: "\n").compactMap { line in
            let f = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard f.count >= 2, seen.insert(f[0]).inserted else { return nil }
            return Remote(name: f[0], url: f[1])
        }
    }

    public func status() throws -> [String: FileStatus] {
        var out: [String: FileStatus] = [:]
        let entries = try git(["status", "--porcelain=v1", "-z", "--untracked-files=all"]).split(separator: "\0", omittingEmptySubsequences: true)
        var i = 0
        while i < entries.count {
            let e = String(entries[i])
            i += 1
            guard e.count > 3 else { continue }
            let x = e[e.startIndex], y = e[e.index(after: e.startIndex)]
            let path = root.appendingPathComponent(String(e.dropFirst(3))).path
            let status: FileStatus
            switch (x, y) {
            case ("?", "?"): status = .untracked
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): status = .conflicted
            case ("R", _):
                status = .renamed
                i += 1
            case ("A", _): status = .added
            case ("D", _), (_, "D"): status = .deleted
            default: status = .modified
            }
            out[path] = status
        }
        return out
    }

    public func headContents(of path: String) -> String? {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        guard p.hasPrefix(root.path + "/") else { return nil }
        return try? git(["show", "HEAD:" + String(p.dropFirst(root.path.count + 1))])
    }

    public func diff(of path: String) -> String { diff(of: path, scope: .all) }

    @discardableResult
    public func commit(files: [String], message: String) throws -> String {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw GitError(description: "empty commit message") }
        let rel = try files.map { path -> String in
            let p = URL(fileURLWithPath: path).standardizedFileURL.path
            guard p.hasPrefix(root.path + "/") else { throw GitError(description: "\(path) is outside the repository") }
            return String(p.dropFirst(root.path.count + 1))
        }
        guard !rel.isEmpty else { throw GitError(description: "no files selected") }
        _ = try git(["add", "--"] + rel)
        _ = try git(["commit", "-m", message, "--"] + rel)
        return try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
