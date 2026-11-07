import Foundation

extension GitRepository {

    public func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-") else { return false }
        return (try? gitStatus(["check-ref-format", "--branch", name]))?.status == 0
    }

    public func isValidTagName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-") else { return false }
        return (try? gitStatus(["check-ref-format", "refs/tags/" + name]))?.status == 0
    }

    func requireBranchName(_ name: String) throws {
        guard isValidBranchName(name) else { throw GitError(description: "\u{201C}\(name)\u{201D} is not a valid branch name.") }
    }

    func requireTagName(_ name: String) throws {
        guard isValidTagName(name) else { throw GitError(description: "\u{201C}\(name)\u{201D} is not a valid tag name.") }
    }

    public func resolve(_ revision: String) -> String? {
        guard !revision.hasPrefix("-") else { return nil }
        let s = (try? git(["rev-parse", "--verify", "--quiet", revision + "^{commit}"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return s?.isEmpty == false ? s : nil
    }

    public func hasTrackedChanges() -> Bool {
        ((try? changes()) ?? []).contains { $0.status != .untracked }
    }

    public func createBranch(_ name: String, from start: String? = nil, checkout: Bool = false) throws {
        try requireBranchName(name)
        if let start, resolve(start) == nil { throw GitError(description: "\u{201C}\(start)\u{201D} does not name a commit.") }
        if checkout {
            _ = try git(["switch", "--no-track", "-c", name] + (start.map { [$0] } ?? []))
        } else {
            _ = try git(["branch", "--no-track", "--", name] + (start.map { [$0] } ?? []))
        }
    }

    public func deleteBranch(_ name: String, force: Bool = false) throws {
        if name == currentBranch() { throw GitError(description: "\u{201C}\(name)\u{201D} is the current branch. Switch to another branch first.") }
        _ = try git(["branch", force ? "-D" : "-d", "--", name])
    }

    public func renameBranch(_ name: String, to newName: String) throws {
        try requireBranchName(newName)
        _ = try git(["branch", "-m", "--", name, newName])
    }

    public enum ChangeHandling: Sendable, Equatable {
        case refuse
        case carry
        case stash
    }

    @discardableResult
    public func checkout(_ name: String, changes handling: ChangeHandling) throws -> String? {
        if (try? status())?.values.contains(.conflicted) == true {
            throw GitError(description: "The working copy has unresolved conflicts. Resolve them before switching branches.")
        }
        var stashed: String?
        switch handling {
        case .refuse:
            if hasTrackedChanges() { throw GitError(description: "The working copy has uncommitted changes. Commit, stash or discard them first.") }
        case .carry: break
        case .stash:
            if !((try? changes()) ?? []).isEmpty {
                try stash(message: "Before switching to \(name)")
                stashed = stashList().first?.ref
            }
        }
        let local = Set(((try? branches()) ?? []).map(\.name))
        if local.contains(name) {
            _ = try git(["switch", "--", name])
        } else if ((try? remoteBranches()) ?? []).contains(where: { $0.name == name }), let slash = name.firstIndex(of: "/") {
            let short = String(name[name.index(after: slash)...])
            if local.contains(short) { _ = try git(["switch", "--", short]) } else { _ = try git(["switch", "-c", short, "--track", name]) }
        } else {
            throw GitError(description: "There is no branch named \u{201C}\(name)\u{201D}.")
        }
        return stashed
    }

    public func checkoutDetached(_ revision: String) throws {
        guard let hash = resolve(revision) else { throw GitError(description: "\u{201C}\(revision)\u{201D} does not name a commit.") }
        _ = try git(["switch", "--detach", hash])
    }

    public func aheadBehind(_ branch: String) -> (ahead: Int, behind: Int)? {
        guard let up = upstream(of: branch),
              let s = try? git(["rev-list", "--left-right", "--count", "refs/heads/\(branch)...\(up)"]) else { return nil }
        let f = s.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).compactMap { Int($0) }
        return f.count == 2 ? (f[0], f[1]) : nil
    }

    public struct Tag: Equatable, Sendable {
        public var name: String
        public var commit: String
        public var message: String
        public var isAnnotated: Bool
    }

    public func tagDetails() -> [Tag] {
        let text = (try? git(["for-each-ref", "--sort=refname",
                              "--format=%(refname)%1f%(objecttype)%1f%(*objectname)%1f%(objectname)%1f%(contents:subject)%1e", "refs/tags"])) ?? ""
        return text.components(separatedBy: Self.recordSeparator).compactMap { rec in
            let f = rec.trimmingCharacters(in: .newlines).components(separatedBy: Self.fieldSeparator)
            guard f.count >= 5, f[0].hasPrefix("refs/tags/") else { return nil }
            let annotated = f[1] == "tag"
            return Tag(name: String(f[0].dropFirst("refs/tags/".count)), commit: annotated ? f[2] : f[3],
                       message: annotated ? f[4] : "", isAnnotated: annotated)
        }
    }

    public func createTag(_ name: String, at revision: String? = nil, message: String? = nil) throws {
        try requireTagName(name)
        let target = revision ?? "HEAD"
        guard resolve(target) != nil else { throw GitError(description: "\u{201C}\(target)\u{201D} does not name a commit.") }
        let m = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _ = try git(["tag"] + (m.isEmpty ? [] : ["-a", "-m", m]) + ["--", name, target])
    }

    public func deleteTag(_ name: String) throws { _ = try git(["tag", "-d", "--", name]) }

    public func addRemote(_ name: String, url: String) throws {
        guard isValidBranchName(name), !url.isEmpty, !url.hasPrefix("-") else { throw GitError(description: "Enter a remote name and URL.") }
        _ = try git(["remote", "add", "--", name, url])
    }

    public func removeRemote(_ name: String) throws { _ = try git(["remote", "remove", "--", name]) }

    public func fetch(remote: String) throws { _ = try git(["fetch", "--prune", "--", remote]) }

    public enum PullStyle: Sendable { case fastForwardOnly, merge, rebase }

    @discardableResult
    public func pull(remote: String, branch: String, style: PullStyle = .fastForwardOnly) throws -> IntegrationResult {
        try fetch(remote: remote)
        let ref = "\(remote)/\(branch)"
        switch style {
        case .fastForwardOnly: return try merge(ref, style: .fastForwardOnly)
        case .merge: return try merge(ref, style: .fastForwardIfPossible)
        case .rebase: return try rebase(onto: ref)
        }
    }

    public func push(remote: String, branch: String, setUpstream: Bool = false, force: Bool = false, forceLease: Bool = true) throws {
        guard !remote.hasPrefix("-"), isValidBranchName(branch) else { throw GitError(description: "Choose a remote and a branch.") }
        let forceFlag = force ? (forceLease ? "--force-with-lease" : "--force") : nil
        _ = try git(["push"] + (setUpstream ? ["--set-upstream"] : []) + (forceFlag.map { [$0] } ?? [])
                    + ["--", remote, "refs/heads/\(branch):refs/heads/\(branch)"])
    }

    public func pushAll(remote: String) throws {
        guard !remote.hasPrefix("-") else { throw GitError(description: "Choose a remote.") }
        _ = try git(["push", "--all", "--", remote])
    }

    public func push(remote: String, tag: String) throws { _ = try git(["push", "--", remote, "refs/tags/\(tag)"]) }
    public func deleteRemoteBranch(remote: String, branch: String) throws {
        _ = try git(["push", "--", remote, ":refs/heads/\(branch)"])
    }
}
