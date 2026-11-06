import Foundation
import YcodeAssistant
import YcodeIDECore
import YcodeSubprocess

/// The ported Legacy Agentic local-git tool family (Wave 8, slice C).
///
/// Behaviour source: Legacy's `AgentTool` implementations in
/// `SwiftCode/Tools/Agentic/` (Dylan's own code, ported under MIT) —
/// `GitStatusTool`, `GitDiffTool`, `GitAddTool`, `GitCommitTool`,
/// `GitCheckoutTool`, `GitBranchTool`, `GitMergeTool`, `GitRebaseTool`,
/// `GitResetTool`, `GitStashTool`, `GitPullTool`, `GitPushTool`,
/// `GitCloneTool`, `GitBlameTool`, `GitLogTool`, `GitShowTool`,
/// `GitTagTool`, `GitCherryPickTool`, `GitRevertTool` and
/// `GitWorktreeTool`. Descriptions are Legacy's verbatim; schemas are
/// Legacy's `schema` verbatim plus the `workspace` parameter Wave 1
/// adds to every tool. The Agentic tools declare no capability, risk
/// level or permission in Legacy (the `AgentTool` protocol carries
/// only `name` / `description` / `schema` / `execute`), so those are
/// derived from behaviour here and recorded in
/// `specs/ide/agentic-git-draft.md`: read-only tools are `safeRead`,
/// mutating tools `safeMutation`, `git_reset` (whose Legacy default
/// is `--hard`) `potentiallyDestructive`; capability is
/// `gitOperations` throughout; permission is `fileSystem` for
/// mutating tools, `none` for read-only ones (Legacy's Assist
/// derivation).
///
/// Conventions, following Wave 3 (`YcodeTools+Git.swift`):
///
/// * Every git operation runs the `git` CLI (via `YcodeSubprocess`,
///   `HostTool.path("git")`) as an argument vector — never a shell —
///   with the repository folder as its working directory, exactly as
///   Legacy's `ProcessRunnerTool` runs do (`/usr/bin/git` there; the
///   Flatpak-aware `HostTool` path here). The environment is Wave 3's
///   `gitEnvironment()`: inherited, minus the variables that could
///   point git at another repository, plus the
///   never-wait-for-a-person settings. A workspace that is not a git
///   repository fails with git's own "not a git repository" message —
///   never invented log/blame/status output.
/// * Workspace confinement: `repositoryPath` resolves with
///   `resolveFileReadingPath` (plain relative paths against the
///   session working directory; an absolute path inside the workspace
///   is used as-is; `..` past the workspace root is an error). File
///   arguments (`file`, `files`) are relativised against the
///   repository folder the same way and must stay inside it.
///   Branch/ref/commit arguments are validated with Wave 3's
///   validators before they reach git. A leading `-` can therefore
///   never be parsed as a git flag.
/// * Approval gating: every mutating git operation gates BEFORE
///   running git, through an explicit `MCPChange` + `call.approve`
///   (the Wave 2 §6.2 shape for non-text operations, reused here via
///   Wave 3's `gitApproveChange`; the change's path is the workspace
///   root, relative path `"."`). The tools are registered
///   `writes: true`, so `MCPServer.run` refuses them in `readOnly`
///   server mode — the same treatment Wave 2 gives dry-run tools.
/// * `git_pull`, `git_push` and `git_clone` are registered but
///   honestly failing: they are remote-only, and this wave must not
///   touch remotes. Their handlers always fail naming the later-wave
///   prerequisite (the Wave 3 `github_repo` precedent). No remote
///   data is fetched and none is faked.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `repositoryPath` is optional in the Ycode schema (Legacy
///   requires it): omitted, the tool operates on the session
///   workspace root, which is the Ycode workspace model. Given, it
///   must stay inside the workspace — Legacy accepted any absolute
///   path, Ycode confines it.
/// * Legacy's read tools return `stdout` unchecked, so a failure
///   (unknown file, unknown ref, no repository) silently returns
///   an empty string. The port throws git's own message on a
///   non-zero exit instead — never an invented empty result.
/// * Legacy passes `branch`, `mode`, `target`, `action` and `hash`
///   to argv unchecked. The port validates them first: branch names
///   with Wave 3's strict allow-list, refs with `gitIsValidRef`,
///   hashes with `gitIsValidCommit`, reset modes against
///   `--soft/--mixed/--hard/--merge/--keep`, stash actions against
///   `push/pop/list/show/drop/apply/clear`, worktree actions
///   against `list/add/remove/move/lock/unlock/prune/repair`.
/// * `git_worktree` keeps Legacy's single-token `action`: `add`,
///   `remove` and `move` need extra arguments Legacy's schema does
///   not provide, so git reports its usage error for them — the
///   Legacy limitation, preserved honestly rather than papered over
///   with an invented schema.
/// * `git_stash show` keeps Legacy's plain form (no `-p`); Wave 3's
///   `git_stash_operator` shows with `-p`.
///
/// ID collisions, resolved by the coordinator at wiring time
/// (Wave 8): eight of these Agentic IDs collided with Assist
/// registrations. Seven were entries in `MCPServer.toolAliases`
/// (`git_status`, `git_diff`, `git_commit`, `git_branch`,
/// `git_stash`, `git_blame`, `git_log` → the operator tools);
/// those aliases are REMOVED, so the Agentic tools registered here
/// own the names — the operator tools stay callable by their own
/// names. The eighth, `git_cherry_pick`, is NOT registered here:
/// the Wave 3 Assist tool was aligned in place instead (it accepts
/// the Agentic `hash` + `repositoryPath` spellings alongside
/// `commit`), so one registration serves both shapes.
extension YcodeMCPHost {
    var agenticGitTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let destructive = MCPToolAnnotations(readOnly: false, destructive: true)
        return [
            tool("git_status", "Git Status",
                 "Returns the status of the git repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace.")])) { h, call in
                try await h.agenticGitStatus(call)
            },
            tool("git_diff", "Git Diff",
                 "Returns the diff of changes in the repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "file": Schema.string("Optional file to diff, as a workspace-relative path.")])) { h, call in
                try await h.agenticGitDiff(call)
            },
            tool("git_add", "Git Add",
                 "Adds files to the git staging area.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "files": Schema.array(Schema.str, "Files to stage, as workspace-relative paths.")],
                                      required: ["files"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitAdd(call)
            },
            tool("git_commit", "Git Commit",
                 "Commits staged changes to the git repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "message": Schema.string("Commit message.")],
                                      required: ["message"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitCommit(call)
            },
            tool("git_checkout", "Git Checkout",
                 "Checks out a Git branch.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "branch": Schema.string("Branch to check out.")],
                                      required: ["branch"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitCheckout(call)
            },
            tool("git_branch", "Git Branch",
                 "Lists Git branches.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace.")])) { h, call in
                try await h.agenticGitBranch(call)
            },
            tool("git_merge", "Git Merge",
                 "Merges a Git branch.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "branch": Schema.string("Branch to merge into the current branch.")],
                                      required: ["branch"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitMerge(call)
            },
            tool("git_rebase", "Git Rebase",
                 "Rebases the current branch onto another branch.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "branch": Schema.string("Branch to rebase onto.")],
                                      required: ["branch"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitRebase(call)
            },
            tool("git_reset", "Git Reset",
                 "Resets the current HEAD to a specified state.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "mode": Schema.string("Reset mode: --soft, --mixed, --hard, --merge, or --keep. Default: --hard."),
                                       "target": Schema.string("Target to reset to. Default: HEAD.")]),
                 annotations: destructive, writes: true) { h, call in
                try await h.agenticGitReset(call)
            },
            tool("git_stash", "Git Stash",
                 "Stashes changes in the working directory.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "action": Schema.string("Stash action: push, pop, list, show, drop, apply, or clear. Default: push.")]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitStash(call)
            },
            tool("git_pull", "Git Pull",
                 "Pulls changes from a remote repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace.")])) { h, call in
                try await h.agenticGitPull(call)
            },
            tool("git_push", "Git Push",
                 "Pushes committed changes to the remote repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace.")])) { h, call in
                try await h.agenticGitPush(call)
            },
            tool("git_clone", "Git Clone",
                 "Clones a Git repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "remoteURL": Schema.string("Remote repository URL to clone."),
                                       "destinationPath": Schema.string("Destination path for the clone.")],
                                      required: ["remoteURL", "destinationPath"])) { h, call in
                try await h.agenticGitClone(call)
            },
            tool("git_blame", "Git Blame",
                 "Shows Git blame for a file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "file": Schema.string("File to blame, as a workspace-relative path.")],
                                      required: ["file"])) { h, call in
                try await h.agenticGitBlame(call)
            },
            tool("git_log", "Git Log",
                 "Shows Git log for a repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace.")])) { h, call in
                try await h.agenticGitLog(call)
            },
            tool("git_show", "Git Show",
                 "Shows details of a Git commit.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "hash": Schema.string("Commit hash to show.")],
                                      required: ["hash"])) { h, call in
                try await h.agenticGitShow(call)
            },
            tool("git_tag", "Git Tag",
                 "Lists Git tags.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace.")])) { h, call in
                try await h.agenticGitTag(call)
            },
            // NOTE (Wave 8): `git_cherry_pick` is NOT registered here —
            // the Wave 3 Assist tool was aligned in place to accept the
            // Agentic `hash` + `repositoryPath` spellings, so one
            // registration serves both shapes (see YcodeTools+Git.swift).
            tool("git_revert", "Git Revert",
                 "Reverts a Git commit.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "hash": Schema.string("Commit hash to revert.")],
                                      required: ["hash"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitRevert(call)
            },
            tool("git_worktree", "Git Worktree",
                 "Manages Git worktrees.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace."),
                                       "action": Schema.string("Worktree action: list, add, remove, move, lock, unlock, prune, or repair.")],
                                      required: ["action"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitWorktree(call)
            },
        ]
    }
}

extension YcodeMCPHost {
    // MARK: - Agentic git helpers (all `agenticGit`-prefixed)

    /// The repository folder a call operates on: Legacy's
    /// `repositoryPath` when given, else the workspace root. The
    /// path resolves inside the workspace (`resolveFileReadingPath`)
    /// and must be a directory.
    func agenticGitRepoDir(_ call: MCPToolCall, in s: WorkspaceSession) throws -> URL {
        guard let raw = call.string("repositoryPath") else { return Self.folder(of: s.model) }
        let url = try resolveFileReadingPath(raw, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("repositoryPath is not a directory: \(raw)")
        }
        return url
    }

    /// A file argument as a path relative to `repoDir`, for argv.
    /// Absolute paths must already be inside the repository;
    /// relative paths resolve against it, and `..` that escapes it
    /// is an error. A leading `-` is rejected so it can never be
    /// parsed as a git flag.
    nonisolated static func agenticGitRepoRelativePath(_ raw: String, repoDir: URL) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPToolError("Empty file path.") }
        guard !trimmed.hasPrefix("-") else { throw MCPToolError("Invalid file path: \(trimmed)") }
        guard !trimmed.contains("\0"), !trimmed.contains("\n"), !trimmed.contains("\r") else {
            throw MCPToolError("Invalid file path: \(trimmed)")
        }
        let root = repoDir.standardizedFileURL.path
        let resolved: URL
        if trimmed.hasPrefix("/") {
            resolved = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            resolved = repoDir.appendingPathComponent(trimmed).standardizedFileURL
        }
        guard Self.isInside(resolved, repoDir) else {
            throw MCPToolError("\(trimmed) is outside the repository \(root)")
        }
        if resolved.path == root { return "." }
        return String(resolved.path.dropFirst(root.count + 1))
    }

    /// Runs git with `args` in `root` (Wave 3's `runGit`); returns
    /// the combined output on success, else throws with `failure`
    /// plus git's own message.
    nonisolated static func agenticGitRun(_ args: [String], in root: URL, failure: String) throws -> String {
        let result = try Self.runGit(args, in: root)
        let output = result.combined
        guard result.status == 0 else {
            throw MCPToolError("\(failure): \(output.isEmpty ? "unknown error" : output)")
        }
        return output
    }

    /// The conflicted files of a stopped merge / cherry-pick /
    /// rebase, from `git status --porcelain` (the two-letter codes
    /// for unmerged paths, as Wave 3's cherry-pick helper does).
    nonisolated static func agenticGitConflictedFiles(in root: URL) -> [String] {
        guard let status = try? runGit(["status", "--porcelain"], in: root), status.status == 0 else { return [] }
        let conflictCodes: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        var files: [String] = []
        for line in status.stdout.components(separatedBy: "\n") {
            guard line.count >= 3 else { continue }
            let code = String(line.prefix(2))
            guard conflictCodes.contains(code) else { continue }
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if !path.isEmpty { files.append(path) }
        }
        return files
    }

    /// Legacy's success string when git printed nothing, else git's
    /// own output — the shape every mutating handler below returns.
    nonisolated static func agenticGitSuccess(output: String, fallback: String) -> MCPToolResult {
        .text(output.isEmpty ? fallback : output)
    }
}

extension YcodeMCPHost {
    // MARK: - Agentic git handlers: read-only

    func agenticGitStatus(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        let result = try Self.runGit(["status", "--porcelain"], in: root)
        guard result.status == 0 else {
            throw MCPToolError("git status failed: \(result.combined.isEmpty ? "unknown error" : result.combined)")
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return .text(out.isEmpty ? "Working tree clean." : result.stdout)
    }

    func agenticGitDiff(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        var args = ["diff"]
        if let file = call.string("file") {
            args.append(try Self.agenticGitRepoRelativePath(file, repoDir: root))
        }
        let result = try Self.runGit(args, in: root)
        guard result.status == 0 else {
            throw MCPToolError("git diff failed: \(result.combined.isEmpty ? "unknown error" : result.combined)")
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return .text(out.isEmpty ? "No changes." : result.stdout)
    }

    func agenticGitBranch(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        let result = try Self.runGit(["branch", "--format=%(refname:short)"], in: root)
        guard result.status == 0 else {
            throw MCPToolError("git branch failed: \(result.combined.isEmpty ? "unknown error" : result.combined)")
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return .text(out.isEmpty ? "No branches in the repository." : result.stdout)
    }

    func agenticGitBlame(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        guard let file = call.string("file") else {
            throw MCPToolError("Missing repositoryPath or file")
        }
        let rel = try Self.agenticGitRepoRelativePath(file, repoDir: root)
        let result = try Self.runGit(["blame", rel], in: root)
        guard result.status == 0 else {
            throw MCPToolError("git blame failed: \(result.combined.isEmpty ? "unknown error" : result.combined)")
        }
        return .text(result.stdout)
    }

    func agenticGitLog(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        let result = try Self.runGit(["log", "--oneline", "-n", "20"], in: root)
        guard result.status == 0 else {
            throw MCPToolError("git log failed: \(result.combined.isEmpty ? "unknown error" : result.combined)")
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return .text(out.isEmpty ? "No commits found in the repository history." : result.stdout)
    }

    func agenticGitShow(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        guard let hash = call.string("hash") else {
            throw MCPToolError("Missing repositoryPath or hash")
        }
        guard Self.gitIsValidCommit(hash) else { throw MCPToolError("Invalid commit: \(hash)") }
        let result = try Self.runGit(["show", hash], in: root)
        guard result.status == 0 else {
            throw MCPToolError("git show failed: \(result.combined.isEmpty ? "unknown error" : result.combined)")
        }
        return .text(result.stdout)
    }

    func agenticGitTag(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        let result = try Self.runGit(["tag"], in: root)
        guard result.status == 0 else {
            throw MCPToolError("git tag failed: \(result.combined.isEmpty ? "unknown error" : result.combined)")
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return .text(out.isEmpty ? "No tags in the repository." : result.stdout)
    }

    // MARK: - Agentic git handlers: mutating (local)

    func agenticGitAdd(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        guard let files = call.strings("files"), !files.isEmpty else {
            throw MCPToolError("Missing repositoryPath or files")
        }
        var rels: [String] = []
        for file in files {
            rels.append(try Self.agenticGitRepoRelativePath(file, repoDir: root))
        }
        try await gitApproveChange(tool: call.name, summary: "Git add \(rels.joined(separator: ", "))", in: s, call: call)
        let output = try Self.agenticGitRun(["add"] + rels, in: root, failure: "Git add failed")
        return Self.agenticGitSuccess(output: output, fallback: "Files added successfully")
    }

    func agenticGitCommit(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        guard let message = call.string("message") else {
            throw MCPToolError("Missing repositoryPath or message")
        }
        try await gitApproveChange(tool: call.name, summary: "Git commit: \(message)", in: s, call: call)
        let output = try Self.agenticGitRun(["commit", "-m", message], in: root, failure: "Git commit failed")
        return Self.agenticGitSuccess(output: output, fallback: "Changes committed successfully")
    }

    func agenticGitCheckout(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        guard let branch = call.string("branch") else {
            throw MCPToolError("Missing repositoryPath or branch")
        }
        guard Self.gitIsValidRefName(branch) else { throw MCPToolError("Invalid branch name: \(branch)") }
        try await gitApproveChange(tool: call.name, summary: "Git checkout \(branch)", in: s, call: call)
        let output = try Self.agenticGitRun(["checkout", branch], in: root, failure: "Git checkout failed")
        return Self.agenticGitSuccess(output: output, fallback: "Successfully checked out branch \(branch)")
    }

    func agenticGitMerge(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        guard let branch = call.string("branch") else {
            throw MCPToolError("Missing repositoryPath or branch")
        }
        guard Self.gitIsValidRefName(branch) else { throw MCPToolError("Invalid branch name: \(branch)") }
        try await gitApproveChange(tool: call.name, summary: "Git merge \(branch)", in: s, call: call)
        let result = try Self.runGit(["merge", branch], in: root)
        let output = result.combined
        guard result.status == 0 else {
            let conflicted = Self.agenticGitConflictedFiles(in: root)
            if !conflicted.isEmpty {
                throw MCPToolError("Merge of \(branch) stopped due to conflicts in: \(conflicted.joined(separator: ", ")). Resolve the conflicts and commit, or run git merge --abort. Git output: \(output)")
            }
            throw MCPToolError("Git merge failed: \(output.isEmpty ? "unknown error" : output)")
        }
        return Self.agenticGitSuccess(output: output, fallback: "Successfully merged branch \(branch)")
    }

    func agenticGitRebase(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        guard let branch = call.string("branch") else {
            throw MCPToolError("Missing repositoryPath or branch")
        }
        guard Self.gitIsValidRefName(branch) else { throw MCPToolError("Invalid branch name: \(branch)") }
        try await gitApproveChange(tool: call.name, summary: "Git rebase onto \(branch)", in: s, call: call)
        let result = try Self.runGit(["rebase", branch], in: root)
        let output = result.combined
        guard result.status == 0 else {
            let conflicted = Self.agenticGitConflictedFiles(in: root)
            if !conflicted.isEmpty {
                throw MCPToolError("Rebase onto \(branch) stopped due to conflicts in: \(conflicted.joined(separator: ", ")). Resolve the conflicts and continue, or run git rebase --abort. Git output: \(output)")
            }
            throw MCPToolError("Git rebase failed: \(output.isEmpty ? "unknown error" : output)")
        }
        return Self.agenticGitSuccess(output: output, fallback: "Successfully rebased onto \(branch)")
    }

    func agenticGitReset(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        let mode = call.string("mode") ?? "--hard"
        let target = call.string("target") ?? "HEAD"
        let allowedModes = ["--soft", "--mixed", "--hard", "--merge", "--keep"]
        guard allowedModes.contains(mode) else {
            throw MCPToolError("Invalid reset mode '\(mode)'. Allowed: --soft, --mixed, --hard, --merge, --keep.")
        }
        guard Self.gitIsValidRef(target) else { throw MCPToolError("Invalid git ref: \(target)") }
        try await gitApproveChange(tool: call.name, summary: "Git reset \(mode) \(target)", in: s, call: call)
        let output = try Self.agenticGitRun(["reset", mode, target], in: root, failure: "Git reset failed")
        return Self.agenticGitSuccess(output: output, fallback: "Successfully reset to \(target) with mode \(mode)")
    }

    func agenticGitStash(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        let action = (call.string("action") ?? "push").lowercased()
        let allowed = ["push", "pop", "list", "show", "drop", "apply", "clear"]
        guard allowed.contains(action) else {
            throw MCPToolError("Unsupported stash action '\(action)'. Valid: push, pop, list, show, drop, apply, clear.")
        }
        // `list` and `show` only report; every other action moves
        // stashed state.
        if action != "list" && action != "show" {
            try await gitApproveChange(tool: call.name, summary: "Git stash \(action)", in: s, call: call)
        }
        let output = try Self.agenticGitRun(["stash", action], in: root, failure: "Git stash \(action) failed")
        return Self.agenticGitSuccess(output: output, fallback: "Successfully executed git stash \(action)")
    }

    // NOTE (Wave 8): no `agenticGitCherryPick` handler — the Wave 3
    // Assist `gitCherryPick` was aligned in place to accept the
    // Agentic `hash` + `repositoryPath` spellings (see
    // YcodeTools+Git.swift), so the Agentic shape is served there.

    func agenticGitRevert(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        guard let hash = call.string("hash") else {
            throw MCPToolError("Missing repositoryPath or hash")
        }
        guard Self.gitIsValidCommit(hash) else { throw MCPToolError("Invalid commit: \(hash)") }
        try await gitApproveChange(tool: call.name, summary: "Revert \(hash)", in: s, call: call)
        let output = try Self.agenticGitRun(["revert", "--no-edit", hash], in: root, failure: "Git revert failed")
        return Self.agenticGitSuccess(output: output, fallback: "Successfully reverted \(hash)")
    }

    func agenticGitWorktree(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        guard let actionRaw = call.string("action") else {
            throw MCPToolError("Missing repositoryPath or action")
        }
        let action = actionRaw.lowercased()
        let allowed = ["list", "add", "remove", "move", "lock", "unlock", "prune", "repair"]
        guard allowed.contains(action), !action.contains(" "), !action.contains("\t") else {
            throw MCPToolError("Unsupported worktree action '\(actionRaw)'. Valid: list, add, remove, move, lock, unlock, prune, repair.")
        }
        // `list` and `prune` only report. The rest change worktrees;
        // `add` / `remove` / `move` need extra arguments Legacy's
        // schema does not provide, so git reports its usage error
        // for them — the Legacy limitation, preserved honestly.
        if action != "list" && action != "prune" {
            try await gitApproveChange(tool: call.name, summary: "Git worktree \(action)", in: s, call: call)
        }
        let output = try Self.agenticGitRun(["worktree", action], in: root, failure: "Git worktree \(action) failed")
        return Self.agenticGitSuccess(output: output, fallback: "Git worktree \(action) completed.")
    }

    // MARK: - Agentic git handlers: remote-only (honestly failing)

    func agenticGitPull(_ call: MCPToolCall) async throws -> MCPToolResult {
        // Honestly failing: Legacy runs `git pull` against a remote,
        // and this wave must not touch remotes. No remote data is
        // fetched and none is faked. Remote operations
        // (push/pull/fetch/clone) are a later wave.
        _ = try session(for: call)
        throw MCPToolError("git_pull needs remote access, which is out of scope for this wave (local operations only). Remote operations (push/pull/fetch/clone) are a later wave.")
    }

    func agenticGitPush(_ call: MCPToolCall) async throws -> MCPToolResult {
        // Honestly failing: Legacy runs `git push` against a remote;
        // see `agenticGitPull`.
        _ = try session(for: call)
        throw MCPToolError("git_push needs remote access, which is out of scope for this wave (local operations only). Remote operations (push/pull/fetch/clone) are a later wave.")
    }

    func agenticGitClone(_ call: MCPToolCall) async throws -> MCPToolResult {
        // Honestly failing: Legacy runs `git clone <remoteURL>
        // <destinationPath>` against a remote; see `agenticGitPull`.
        _ = try session(for: call)
        throw MCPToolError("git_clone needs remote access, which is out of scope for this wave (local operations only). Remote operations (push/pull/fetch/clone) are a later wave.")
    }
}
