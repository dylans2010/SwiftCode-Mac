import Foundation

extension GitRepository {
    public enum IntegrationResult: Equatable, Sendable {
        case upToDate
        case fastForwarded
        case completed(head: String)
        case conflicts([String])
    }

    public enum IntegrationState: Equatable, Sendable {
        case none
        case merging(branch: String)
        case rebasing(branch: String, onto: String, step: Int, total: Int)
        case cherryPicking(commit: String)
        case reverting(commit: String)

        public var isInProgress: Bool { self != .none }

        public var verb: String {
            switch self {
            case .none: ""
            case .merging: "Merge"
            case .rebasing: "Rebase"
            case .cherryPicking: "Cherry-Pick"
            case .reverting: "Revert"
            }
        }
    }

    public enum MergeStyle: Sendable {
        case fastForwardIfPossible
        case fastForwardOnly
        case mergeCommit
    }

    public func gitDirectory() -> URL? {
        let s = (try? git(["rev-parse", "--absolute-git-dir"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }

    public func integrationState() -> IntegrationState {
        guard let dir = gitDirectory() else { return .none }
        let fm = FileManager.default
        func read(_ name: String) -> String? {
            (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for folder in ["rebase-merge", "rebase-apply"] where fm.fileExists(atPath: dir.appendingPathComponent(folder).path) {
            var head = read("\(folder)/head-name") ?? ""
            if head.hasPrefix("refs/heads/") { head = String(head.dropFirst("refs/heads/".count)) }
            let onto = read("\(folder)/onto").map { String($0.prefix(7)) } ?? ""
            let step = Int(read(folder == "rebase-merge" ? "\(folder)/msgnum" : "\(folder)/next") ?? "") ?? 0
            let total = Int(read(folder == "rebase-merge" ? "\(folder)/end" : "\(folder)/last") ?? "") ?? 0
            return .rebasing(branch: head, onto: onto, step: step, total: total)
        }
        if let head = read("MERGE_HEAD") {
            return .merging(branch: Self.mergedName(read("MERGE_MSG")) ?? String(head.prefix(7)))
        }
        if let c = read("CHERRY_PICK_HEAD") { return .cherryPicking(commit: c) }
        if let c = read("REVERT_HEAD") { return .reverting(commit: c) }
        return .none
    }

    static func mergedName(_ message: String?) -> String? {
        guard let first = message?.split(separator: "\n").first, first.hasPrefix("Merge "),
              let open = first.firstIndex(of: "'"), let close = first[first.index(after: open)...].firstIndex(of: "'") else { return nil }
        return String(first[first.index(after: open)..<close])
    }

    public func conflictedFiles() -> [String] {
        let text = (try? git(["diff", "--name-only", "--diff-filter=U", "-z"])) ?? ""
        return Set(text.split(separator: "\0").map { root.appendingPathComponent(String($0)).path }).sorted()
    }

    private func integrationOutcome(_ r: (status: Int32, stdout: String, stderr: String), before: String?) throws -> IntegrationResult {
        if r.status == 0 {
            let head = headHash()
            if head == before { return .upToDate }
            if r.stdout.contains("Fast-forward") || r.stdout.contains("Fast forward") { return .fastForwarded }
            return .completed(head: head ?? "")
        }
        let conflicts = conflictedFiles()
        if !conflicts.isEmpty { return .conflicts(conflicts) }
        let message = (r.stderr + "\n" + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        throw GitError(description: message.isEmpty ? "git stopped with status \(r.status)." : message)
    }

    private func runIntegrating(_ args: [String]) throws -> IntegrationResult {
        let before = headHash()
        let r = try gitStatus(args)
        return try integrationOutcome((r.status, r.stdoutText, r.stderrText), before: before)
    }

    @discardableResult
    public func merge(_ revision: String, style: MergeStyle = .fastForwardIfPossible, message: String? = nil) throws -> IntegrationResult {
        guard resolve(revision) != nil else { throw GitError(description: "\u{201C}\(revision)\u{201D} does not name a commit.") }
        let flag = switch style {
        case .fastForwardIfPossible: "--ff"
        case .fastForwardOnly: "--ff-only"
        case .mergeCommit: "--no-ff"
        }
        let m = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try runIntegrating(["merge", "--no-edit", flag] + (m.isEmpty ? [] : ["-m", m]) + [revision])
    }

    @discardableResult
    public func rebase(onto revision: String) throws -> IntegrationResult {
        guard resolve(revision) != nil else { throw GitError(description: "\u{201C}\(revision)\u{201D} does not name a commit.") }
        return try runIntegrating(["rebase", revision])
    }

    @discardableResult
    public func cherryPickCommit(_ revision: String) throws -> IntegrationResult {
        guard resolve(revision) != nil else { throw GitError(description: "\u{201C}\(revision)\u{201D} does not name a commit.") }
        return try runIntegrating(["cherry-pick", revision])
    }

    @discardableResult
    public func revert(_ revision: String) throws -> IntegrationResult {
        guard resolve(revision) != nil else { throw GitError(description: "\u{201C}\(revision)\u{201D} does not name a commit.") }
        return try runIntegrating(["revert", "--no-edit", revision])
    }

    @discardableResult
    public func continueIntegration() throws -> IntegrationResult {
        let state = integrationState()
        let unresolved = conflictedFiles()
        guard unresolved.isEmpty else {
            throw GitError(description: "\(unresolved.count) file\(unresolved.count == 1 ? " has" : "s have") unresolved conflicts.")
        }
        switch state {
        case .none: throw GitError(description: "No merge, rebase or cherry-pick is in progress.")
        case .merging: return try runIntegrating(["commit", "--no-edit"])
        case .rebasing: return try runIntegrating(["rebase", "--continue"])
        case .cherryPicking:
            if (try? gitStatus(["diff", "--cached", "--quiet"]))?.status == 0 { return try runIntegrating(["cherry-pick", "--skip"]) }
            return try runIntegrating(["cherry-pick", "--continue"])
        case .reverting: return try runIntegrating(["revert", "--continue"])
        }
    }

    public func abortIntegration() throws {
        switch integrationState() {
        case .none: throw GitError(description: "No merge, rebase or cherry-pick is in progress.")
        case .merging: _ = try git(["merge", "--abort"])
        case .rebasing: _ = try git(["rebase", "--abort"])
        case .cherryPicking: _ = try git(["cherry-pick", "--abort"])
        case .reverting: _ = try git(["revert", "--abort"])
        }
    }

    public struct Stash: Equatable, Sendable {
        public var ref: String
        public var description: String
        public var message: String {
            for p in ["WIP on ", "On "] where description.hasPrefix(p) {
                if let colon = description.range(of: ": ") { return String(description[colon.upperBound...]) }
            }
            return description
        }
    }

    public func stashList() -> [Stash] {
        stashes().compactMap { line in
            guard let r = line.range(of: ": ") else { return nil }
            return Stash(ref: String(line[..<r.lowerBound]), description: String(line[r.upperBound...]))
        }
    }

    @discardableResult
    public func applyStash(_ ref: String, pop: Bool = false) throws -> IntegrationResult {
        guard ref.hasPrefix("stash@{") else { throw GitError(description: "\u{201C}\(ref)\u{201D} is not a stash.") }
        let r = try gitStatus(["stash", pop ? "pop" : "apply", ref])
        if r.status == 0 { return .completed(head: headHash() ?? "") }
        let conflicts = conflictedFiles()
        if !conflicts.isEmpty { return .conflicts(conflicts) }
        throw GitError(description: (r.stderrText + r.stdoutText).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func dropStash(_ ref: String) throws {
        guard ref.hasPrefix("stash@{") else { throw GitError(description: "\u{201C}\(ref)\u{201D} is not a stash.") }
        _ = try git(["stash", "drop", "-q", ref])
    }

    public func files(inStash ref: String) -> [(path: String, status: FileStatus)] {
        guard ref.hasPrefix("stash@{") else { return [] }
        let text = (try? git(["diff", "--name-status", "-M", "\(ref)^1", ref, "--"])) ?? ""
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
}
