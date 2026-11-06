import Foundation
import YcodeAssistant
import YcodeIDECore
import YcodeSubprocess

/// The ported Legacy Git / source-control tool family (Wave 3, Git slice).
///
/// Behaviour source: Legacy's `AssistConflictMarkerScanTool`,
/// `AssistGitBisectTool`, `AssistGitBlameTool`,
/// `AssistGitBranchCompareTool`, `AssistGitBranchManagerTool`,
/// `AssistGitCherryPickTool`, `AssistGitConflictResolverTool`,
/// `AssistGitLogViewerTool`, `AssistGitPRSummaryTool`,
/// `AssistGitStashTool`, `AssistGitHubRepoTool`,
/// `AssistRecentChangesTool` and `AssistVersionControlOperator`
/// (Dylan's own code, ported under MIT), plus `AssistTool.swift` for
/// the capability/risk/permission defaults and
/// `AssistToolRegistry.swift` for the alias table. Schemas below are
/// Legacy's `parametersSchema` verbatim, plus the `workspace`
/// parameter Wave 1 adds to every tool; descriptions are Legacy's
/// verbatim. Structured data keeps Legacy's keys, with typed JSON
/// values (integers and booleans) the way Ycode's other tools do —
/// Legacy's string-only map is not reproduced. Tools whose Legacy
/// result carries no data return a plain text result instead.
///
/// Conventions, following Wave 1 (`YcodeTools+FileReading.swift`) and
/// Wave 2 (`YcodeTools+FileWriting.swift`):
///
/// * Every git operation runs the `git` CLI (via `YcodeSubprocess`,
///   `HostTool.path("git")`) as an argument vector — never a shell —
///   with the workspace folder as its working directory, exactly as
///   Legacy's `runGit` helpers do (`/usr/bin/git` there; the
///   Flatpak-aware `HostTool` path here). The environment mirrors
///   `GitRepository.environment`: inherited, minus the variables
///   that could point git at another repository, plus the
///   never-wait-for-a-person settings. Nothing here touches a
///   remote: there is no push/pull/fetch/clone, and no GitHub API
///   call anywhere in this file.
/// * Workspace confinement: paths resolve with
///   `resolveFileReadingPath` (plain relative paths against the
///   session working directory; `..` past the workspace root is an
///   error). Branch/ref/commit arguments are validated with
///   Legacy's own validators before they reach git. A workspace
///   that is not a git repository fails with git's own "not a git
///   repository" message — never invented log/blame/status output.
/// * Approval gating: every mutating git operation gates BEFORE
///   running git, through an explicit `MCPChange` + `call.approve`
///   (the Wave 2 §6.2 shape for non-text operations; the change's
///   path is the workspace root, relative path `"."`). Text
///   resolution in `git_conflict_resolver` goes through `commit()`
///   instead (Wave 2 §6.1). Read-only actions of a writing tool
///   (`git_bisect` log, `git_branch_manager` list/current,
///   `git_stash_operator` list/show,
///   `version_control_operator` status/diff) request no approval,
///   but the tool is still registered `writes: true`, so
///   `MCPServer.run` refuses them in `readOnly` server mode — the
///   same treatment Wave 2 gives dry-run tools.
/// * `github_repo` is registered but honestly failing: Ycode's MCP
///   host has no GitHub API client and no GitHub credential, so its
///   handler always fails naming that prerequisite. No GitHub data
///   is faked. (Wave 2's `code_refactor` precedent.)
///
/// Ycode's existing source-control seams, and why they are (mostly)
/// not the implementation here:
///
/// * `GitRepository` (`YcodeIDECore/Model/GitRepository.swift`) runs
///   git the same way, but its methods return IDE shapes (a `Ref`
///   list, a status map, parsed blame commits) that do not
///   reproduce Legacy's verbatim git output, and most of these
///   operations (bisect, cherry-pick, stash push/pop/list, `log`
///   with a format, `diff --stat`) have no seam method at all. The
///   one runner is therefore shared here, and the seams are used
///   only where they fit Legacy's behaviour exactly: none of the
///   thirteen tools routes through `GitRepository` — see the notes
///   below for the two near-misses.
/// * `GitBlame.parse` is not used by `git_blame_inspector`:
///   Legacy's output is the `git blame -s` rendering (short hash,
///   author, date, line number, line text), and the parse drops the
///   line text, so it cannot reproduce that output. The tool runs
///   the same two git commands Legacy runs.
/// * `GitRepository.resolveConflict(path:text:)` is not used by
///   `git_conflict_resolver`: it also stages the file (`git add`),
///   while Legacy only writes the resolved text. The tool writes
///   through `commit()` like every other Ycode text write.
/// * `GitRepository.commit(files:message:)` is not used by
///   `version_control_operator`: Legacy stages everything
///   (`git add -A`) and commits with a default message, which that
///   seam does not do.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `git_bisect` declares Legacy risk `.execution`, which the
///   Wave 1/2 risk table (§1.3/§27.2) does not cover (it covers
///   only `safeRead` / `safeMutation` / `potentiallyDestructive`).
///   `.execution` ranks between `safeMutation` and
///   `potentiallyDestructive` in Legacy, and bisect moves the
///   checkout, so the port maps it to `readOnly: false,
///   idempotent: false`, `writes: true`, with the approval gate on
///   every action except `log`. Legacy's derived permission for it
///   is `none` (only mutating tools require `fileSystem`, and
///   `.execution` is not mutating by that derivation).
/// * `git_cherry_pick`'s `noCommit` keeps Legacy's **string** schema
///   type (`"true"` / `"1"` / `"yes"`), not a boolean — Legacy
///   declares it a string and parses it with its `boolValue`.
/// * `git_conflict_resolver` does NOT reproduce Legacy's
///   absolute-path carve-out (a leading-`/` path used as a raw
///   filesystem path, which could resolve conflicts outside the
///   workspace). Paths resolve inside the workspace like every
///   other Ycode tool.
/// * `version_control_operator` drops Legacy's `#if os(macOS)`
///   gate ("Version control operations require macOS runtime"):
///   the git CLI exists on Linux too, so the port runs there.
/// * Ref/branch validation is tightened where Legacy passed raw
///   strings to argv: `git_branch_manager` and
///   `version_control_operator` validate branch names with the
///   strict allow-list Legacy's `version_control_operator` uses,
///   and `git_stash_operator` validates `stashIndex` as
///   `stash@{N}` (or a plain number). An argument vector cannot
///   inject shell, but a leading `-` could otherwise be parsed as
///   a git flag.
/// * `git_pr_summary` is implemented locally, not honestly
///   failing: Legacy's own description says it uses "only local
///   git history. No network, no GitHub API", and its
///   implementation is four local git commands.
/// * `version_control_operator` has no remote sub-operations in
///   Legacy (only status/commit/branch/rollback/diff); the
///   push/pull/fetch/clone actions named in the wave brief are
///   rejected with an explicit error naming the later-wave
///   prerequisite, rather than Legacy's generic unknown-action
///   error.
extension YcodeMCPHost {
    var gitTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let destructive = MCPToolAnnotations(readOnly: false, destructive: true)
        // `git_bisect`'s Legacy risk `.execution`: mutates the
        // checkout, but is neither `safeMutation` nor
        // `potentiallyDestructive` — not idempotent, not destructive.
        let execution = MCPToolAnnotations(readOnly: false, idempotent: false)
        return [
            tool("conflict_marker_scan", "Conflict Marker Scan",
                 "Scans source files for unresolved merge-conflict markers (<<<<<<<, =======, >>>>>>>).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "limit": Schema.integer("Maximum files to report. Default 50.", minimum: 1)]),
                 output: Schema.output(["fileCount": Schema.int])) { h, call in
                try await h.conflictMarkerScan(call)
            },
            tool("git_bisect", "Git Bisect",
                 "Runs one step of git bisect (start, good, bad, skip, reset, or log) in the workspace repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Bisect action: start, good, bad, skip, reset, or log. Default: log."),
                                       "ref": Schema.string("Commit ref for the good or bad action.")]),
                 output: Schema.output(["action": Schema.str, "output": Schema.str]),
                 annotations: execution, writes: true) { h, call in
                try await h.gitBisect(call)
            },
            tool("git_blame_inspector", "Git Blame Inspector",
                 "Inspects author, commit hash, date, and commit message for specific lines in a workspace file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to the file in workspace."),
                                       "startLine": Schema.integer("Optional starting line number.", minimum: 1),
                                       "endLine": Schema.integer("Optional ending line number.", minimum: 1)],
                                      required: ["path"])) { h, call in
                try await h.gitBlameInspector(call)
            },
            tool("git_branch_compare", "Compare Branches",
                 "Compares two branches with diff stat plus the commits in head not in base.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "base": Schema.string("Base branch or ref."),
                                       "head": Schema.string("Head branch or ref.")],
                                      required: ["base", "head"]),
                 output: Schema.output(["base": Schema.str, "head": Schema.str, "commits": Schema.str,
                                        "diffStat": Schema.str, "commitCount": Schema.int])) { h, call in
                try await h.gitBranchCompare(call)
            },
            tool("git_branch_manager", "Git Branch Manager",
                 "Inspects, lists, creates, switches, and manages Git branches in the workspace.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'list', 'current', 'create', 'switch', or 'delete'."),
                                       "branchName": Schema.string("Branch name when creating, switching, or deleting.")],
                                      required: ["action"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.gitBranchManager(call)
            },
            tool("git_cherry_pick", "Git Cherry-Pick",
                 "Cherry-picks one commit onto the current branch. On conflict it reports the conflicted files and leaves the state for manual resolution.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "commit": Schema.string("Full or short commit SHA, or a validated ref to cherry-pick."),
                                       "noCommit": Schema.string("Pass \"true\" to stage the change without committing (--no-commit). Default: false.")],
                                      required: ["commit"]),
                 output: Schema.output(["commit": Schema.str, "output": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.gitCherryPick(call)
            },
            tool("git_conflict_resolver", "Git Conflict Resolver",
                 "Detects, inspects, and helps resolve Git merge conflict markers in workspace source files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to file with merge conflicts."),
                                       "resolution": Schema.string("Optional resolution strategy: 'inspect', 'take_ours', 'take_theirs'. Defaults to 'inspect'.")],
                                      required: ["path"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.gitConflictResolver(call)
            },
            tool("git_log_viewer", "Git Log Viewer",
                 "Retrieves structured commit history, commit hashes, dates, authors, and changed file stats.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "maxCount": Schema.integer("Maximum number of commits to retrieve (default: 15).", minimum: 1),
                                       "path": Schema.string("Optional specific file or directory path to filter log history for.")])) { h, call in
                try await h.gitLogViewer(call)
            },
            tool("git_pr_summary", "PR Summary",
                 "Builds a local markdown PR summary (commits, files changed, insertions/deletions) for head versus base using only local git history. No network, no GitHub API.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "base": Schema.string("Base branch or ref. Default: main."),
                                       "head": Schema.string("Head branch or ref. Default: HEAD.")]),
                 output: Schema.output(["summary": Schema.str, "base": Schema.str, "head": Schema.str, "commitCount": Schema.int,
                                        "fileCount": Schema.int, "insertions": Schema.int, "deletions": Schema.int,
                                        "shortstat": Schema.str])) { h, call in
                try await h.gitPRSummary(call)
            },
            tool("git_stash_operator", "Git Stash Operator",
                 "Manages Git stashes (save, pop, list, show, drop) to safely stash and restore changes during refactoring.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'save', 'pop', 'list', 'show', 'drop'."),
                                       "message": Schema.string("Optional descriptive message for 'save'."),
                                       "stashIndex": Schema.string("Stash identifier for pop/show/drop (e.g. 'stash@{0}', defaults to 'stash@{0}').")],
                                      required: ["action"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.gitStashOperator(call)
            },
            tool("github_repo", "GitHub Repository Inspector",
                 "Reads real GitHub repositories: metadata, file trees, directory listings, source file contents, code search, and bounded full-repository retrieval. Public repos need no login; private repos use the user's saved GitHub credential.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "operation": Schema.string("One of: repository_info, list_files, get_file, get_directory, get_tree, search_code, fetch_repository."),
                                       "owner": Schema.string("Repository owner or organization, e.g. 'dylans2010'."),
                                       "repo": Schema.string("Repository name, e.g. 'SwiftCode-Mac'."),
                                       "url": Schema.string("GitHub repository URL, e.g. https://github.com/dylans2010/SwiftCode-Mac. Alternative to owner+repo."),
                                       "ref": Schema.string("Branch, tag, or commit SHA. Defaults to the repository's default branch."),
                                       "path": Schema.string("Repository-relative file or directory path for list_files, get_file, get_directory."),
                                       "recursive": Schema.boolean("For get_tree: fetch the full recursive tree (default true). For list_files: recurse into subdirectories via the tree."),
                                       "includeContent": Schema.boolean("For list_files/get_directory: also fetch each file's content (bounded by maxBytes). Default false."),
                                       "maxResults": Schema.integer("Maximum entries/files/matches to return. Defaults: 100 (listings), 5000 (tree), 50 (search), 50 (fetch_repository).", minimum: 1),
                                       "maxBytes": Schema.integer("Maximum aggregate content bytes to return (fetch_repository, includeContent). Default 262144 (256 KB), hard cap 2097152 (2 MB).", minimum: 1),
                                       "query": Schema.string("For search_code: text to find. For fetch_repository: prioritizes files whose path or name matches.")],
                                      required: ["operation"])) { h, call in
                try await h.gitHubRepo(call)
            },
            tool("recent_changes", "Recent Changes",
                 "Lists workspace files modified within the last N hours, newest first. Catches local edits regardless of git state.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "hours": Schema.integer("Look-back window in hours. Default 24, max 720.", minimum: 1),
                                       "limit": Schema.integer("Maximum files to return. Default 50, max 500.", minimum: 1)]),
                 output: Schema.output(["count": Schema.int, "hours": Schema.int])) { h, call in
                try await h.recentChanges(call)
            },
            tool("version_control_operator", "Version Control Operator",
                 "Performs branch, commit, rollback, and diff operations using git.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("The git action to perform: status, commit, branch, rollback, or diff. Unknown actions are rejected."),
                                       "message": Schema.string("The commit message (used for commit action)."),
                                       "name": Schema.string("The branch name (used for branch action)."),
                                       "ref": Schema.string("The git ref to reset to (used for rollback action). Default: HEAD~1. Must match the strict ref pattern; shell metacharacters are rejected.")],
                                      required: ["action"]),
                 output: Schema.output(["output": Schema.str]),
                 annotations: destructive, writes: true) { h, call in
                try await h.versionControlOperator(call)
            },
        ]
    }
}

extension YcodeMCPHost {
    // MARK: - Git runner and validators (shared by the Git tools)

    /// One git run's result. `combined` is stdout then stderr, trimmed —
    /// Legacy merged both pipes into one, and its messages report that
    /// merged text.
    struct GitRunOutput {
        var status: Int32
        var stdout: String
        var stderr: String
        var combined: String {
            [stdout, stderr].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The environment every git command runs with: a mirror of
    /// `GitRepository.environment` (`YcodeIDECore`, internal there, so
    /// restated here) — this process's environment, minus anything
    /// that points git at another repository, plus settings that keep
    /// git from ever waiting for a person, and `GIT_OPTIONAL_LOCKS=0`
    /// so reads never rewrite the index.
    nonisolated static func gitEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
                    "GIT_COMMON_DIR", "GIT_NAMESPACE", "GIT_PREFIX", "GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM",
                    "SSH_ASKPASS", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT"] {
            env[key] = nil
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
        return env
    }

    /// Runs `git` with `args` as an argument vector (never a shell) in
    /// `directory` (the workspace folder; git discovers the repository
    /// upward from there, as Legacy's `runGit` does). Throws only when
    /// git cannot start; a non-zero exit is returned, never thrown, so
    /// the caller reports git's own message — including "not a git
    /// repository" for a workspace with no repository, never invented
    /// output.
    nonisolated static func runGit(_ args: [String], in directory: URL) throws -> GitRunOutput {
        let out: Subprocess.Output
        do {
            out = try Subprocess.run(HostTool.path("git"), args, environment: gitEnvironment(), currentDirectory: directory)
        } catch {
            throw MCPToolError("Failed to launch git: \(error.localizedDescription)")
        }
        return GitRunOutput(status: out.status, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Asks the approval path about one git operation before it runs
    /// (the Wave 2 §6.2 shape for non-text operations): the change's
    /// path is the workspace root, since a git operation has no single
    /// file. Text resolution in `git_conflict_resolver` uses
    /// `commit()` instead.
    func gitApproveChange(tool: String, summary: String, in s: WorkspaceSession, call: MCPToolCall) async throws {
        let root = Self.folder(of: s.model)
        let change = MCPChange(tool: tool, path: root.path, relativePath: ".", original: nil, proposed: "", summary: summary)
        guard await call.approve(change) else { throw MCPToolError(MCPServer.rejectedMessage) }
    }

    /// Legacy's shared ref validator (`AssistGitBisectTool`,
    /// `AssistGitBranchCompareTool`, `AssistGitPRSummaryTool`,
    /// `AssistGitCherryPickTool` all carry the same copy): `HEAD`
    /// and `HEAD~N` / `HEAD^N` forms pass; anything with a space,
    /// shell metacharacter, `..`, `~`, `^`, `:`, `?`, `*`, `[`, a
    /// leading `-`, `@{`, a leading/trailing `/` or `//` fails.
    nonisolated static func gitIsValidRef(_ ref: String) -> Bool {
        guard !ref.isEmpty else { return false }
        if ref == "@" { return false }
        if ref.hasPrefix("-") { return false }
        if ref.contains("@{") { return false }
        if ref == "HEAD" { return true }
        if ref.hasPrefix("HEAD~") || ref.hasPrefix("HEAD^") {
            let tail = String(ref.dropFirst(4))
            var index = tail.startIndex
            while index < tail.endIndex {
                let marker = tail[index]
                guard marker == "~" || marker == "^" else { return false }
                index = tail.index(after: index)
                var digitCount = 0
                while index < tail.endIndex, tail[index].isNumber {
                    digitCount += 1
                    index = tail.index(after: index)
                }
                guard digitCount > 0 else { return false }
            }
            return true
        }
        let forbidden = [" ", ";", "&", "|", "`", "$", "(", ")", "<", ">", "\"", "'", "\\", "\n", "\r", "\t",
                         "..", "~", "^", ":", "?", "*", "["]
        for item in forbidden where ref.contains(item) { return false }
        if ref.contains("\0") { return false }
        if ref.hasPrefix("/") || ref.hasSuffix("/") || ref.contains("//") { return false }
        return true
    }

    /// Legacy `AssistGitCherryPickTool.isValidCommit`: a 7–40 hex SHA,
    /// or a valid ref.
    nonisolated static func gitIsValidCommit(_ value: String) -> Bool {
        if value.hasPrefix("-") { return false }
        if value.contains("\0") || value.contains("\n") || value.contains("\r") { return false }
        if value.count >= 7, value.count <= 40, value.allSatisfy({ $0.isHexDigit }) { return true }
        return gitIsValidRef(value)
    }

    /// Legacy `AssistVersionControlOperator.isValidRefName` (the strict
    /// allow-list): letters, digits, `.` `_` `/` `-`, plus the `HEAD`
    /// and `HEAD[~^]N` forms; at most 256 characters; no `..`, no
    /// leading/trailing `/`, no `.lock` suffix — and, tightened here,
    /// no leading `-` or `.` (a leading `-` could otherwise be parsed
    /// as a git flag). Used for branch names and rollback refs.
    nonisolated static func gitIsValidRefName(_ ref: String) -> Bool {
        guard !ref.isEmpty, ref.count <= 256 else { return false }
        if ref == "HEAD" { return true }
        if ref.hasPrefix("HEAD"), ref.count > 5 {
            let tail = ref.dropFirst(4)
            if tail.count >= 2, (tail.first == "~" || tail.first == "^"), tail.dropFirst().allSatisfy({ $0.isNumber }) { return true }
        }
        guard !ref.hasPrefix("-"), !ref.hasPrefix(".") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/-"))
        guard ref.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard !ref.contains("..") else { return false }
        guard !ref.hasPrefix("/") && !ref.hasSuffix("/") && !ref.hasSuffix(".lock") else { return false }
        return true
    }

    /// A stash identifier for `git_stash_operator` pop/show/drop:
    /// Legacy passed it through unchecked; the port accepts only
    /// `stash@{N}` or a plain number, so a leading `-` can never be
    /// parsed as a git flag.
    nonisolated static func gitIsValidStashRef(_ ref: String) -> Bool {
        if !ref.isEmpty, ref.allSatisfy({ $0.isNumber }) { return true }
        guard ref.hasPrefix("stash@{"), ref.hasSuffix("}") else { return false }
        let middle = ref.dropFirst("stash@{".count).dropLast()
        return !middle.isEmpty && middle.allSatisfy({ $0.isNumber })
    }

    /// Legacy `AssistGitCherryPickTool.boolValue`: a boolean, or the
    /// strings `"true"` / `"1"` / `"yes"` (case-insensitive, trimmed).
    nonisolated static func gitBoolValue(_ value: AnyJSON?) -> Bool {
        if let bool = value?.bool { return bool }
        if let string = value?.string {
            let lowered = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lowered == "true" || lowered == "1" || lowered == "yes"
        }
        return false
    }

    // MARK: - Workspace scans (Legacy `AssistWorkspaceScan`)

    /// Files under `root`, skipping hidden files and the top-level
    /// VCS/build/dependency directories Legacy skips (`.git`,
    /// `.build`, `build`, `DerivedData`, `.swiftpm`, `Pods`,
    /// `Carthage`, `node_modules`, `.venv`), at most 20,000 files.
    /// `extensions` filters by lowercase extension when given
    /// (the source extensions `conflict_marker_scan` uses). Legacy
    /// checks only the FIRST path component against the skip list,
    /// so a nested `build` directory is not skipped — reproduced
    /// here.
    nonisolated static func gitScanFiles(under root: URL, extensions: Set<String>? = nil) -> [URL] {
        let skippedDirs: Set<String> = [".git", ".build", "build", "DerivedData", ".swiftpm",
                                        "Pods", "Carthage", "node_modules", ".venv"]
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles]) else { return results }
        let rootPath = root.standardized.path
        while let url = enumerator.nextObject() as? URL, results.count < 20_000 {
            let rel = url.standardized.path.replacingOccurrences(of: rootPath + "/", with: "")
            if skippedDirs.contains(rel.split(separator: "/").first.map(String.init) ?? "") { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            if let exts = extensions, !exts.contains(url.pathExtension.lowercased()) { continue }
            results.append(url)
        }
        return results
    }

    /// Legacy `AssistGitPRSummaryTool.numberBefore`: the integer
    /// immediately before `marker` in `text` (e.g. `3` before
    /// `"file"` in `" 3 files changed, 10 insertions(+)"`).
    nonisolated static func gitNumberBefore(_ marker: String, in text: String) -> Int {
        guard let range = text.range(of: marker) else { return 0 }
        let before = text[..<range.lowerBound]
        var digits = ""
        for ch in before.reversed() {
            if ch.isNumber {
                digits.insert(ch, at: digits.startIndex)
            } else if ch == " " || ch == "," {
                if !digits.isEmpty { break }
            } else {
                break
            }
        }
        return Int(digits) ?? 0
    }

    /// ISO-8601 timestamps for `recent_changes` (Legacy
    /// `AssistWorkspacePaths.iso8601`).
    nonisolated static func gitISO8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

extension YcodeMCPHost {
    // MARK: - Git tool handlers

    func conflictMarkerScan(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let limit = max(1, min(500, call.int("limit") ?? 50))
        let root = Self.folder(of: s.model)
        // Source files only (Legacy `AssistWorkspaceScan.sourceExts`).
        let sourceExts: Set<String> = ["swift", "m", "mm", "h", "c", "cpp", "hpp"]
        var hits: [(String, [Int])] = []
        for url in Self.gitScanFiles(under: root, extensions: sourceExts) {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var markerLines: [Int] = []
            for (i, line) in content.components(separatedBy: .newlines).enumerated() {
                if line.hasPrefix("<<<<<<<") || line.hasPrefix("=======") || line.hasPrefix(">>>>>>>") {
                    markerLines.append(i + 1)
                }
            }
            if !markerLines.isEmpty {
                hits.append((fileReadingRelativePath(of: url, in: s), markerLines))
                if hits.count >= limit { break }
            }
        }
        if hits.isEmpty {
            return .structured(["fileCount": .int(0)], summary: "No merge-conflict markers found in source files.")
        }
        var lines = ["Files with unresolved conflict markers (\(hits.count)):"]
        for (path, nums) in hits.sorted(by: { $0.0 < $1.0 }) {
            lines.append("- \(path): lines \(nums.prefix(10).map(String.init).joined(separator: ", "))")
        }
        return .structured(["fileCount": .int(hits.count)], summary: lines.joined(separator: "\n"))
    }

    func gitBisect(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let action = (call.arguments["action"]?.string ?? "log").lowercased()
        let allowed = ["start", "good", "bad", "skip", "reset", "log"]
        guard allowed.contains(action) else {
            throw MCPToolError("Invalid bisect action '\(action)'. Allowed: start, good, bad, skip, reset, log.")
        }
        var args = ["bisect", action]
        if action == "good" || action == "bad" {
            if let refRaw = call.arguments["ref"]?.string {
                let ref = refRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !ref.isEmpty {
                    guard Self.gitIsValidRef(ref) else { throw MCPToolError("Invalid git ref: \(ref)") }
                    args.append(ref)
                }
            }
        }
        // `log` only reports; every other step moves the checkout.
        if action != "log" {
            try await gitApproveChange(tool: call.name, summary: "Git bisect \(action)\(args.count > 2 ? " \(args[2])" : "")", in: s, call: call)
        }
        let root = Self.folder(of: s.model)
        let result = try Self.runGit(args, in: root)
        let output = result.combined
        guard result.status == 0 else {
            throw MCPToolError("Git bisect \(action) failed: \(output.isEmpty ? "unknown error" : output)")
        }
        let display = output.isEmpty ? "Git bisect \(action) completed with no output." : output
        return .structured(["action": .string(action), "output": .string(output)],
                           summary: "Git bisect \(action) succeeded.\n\(display)")
    }

    func gitBlameInspector(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let startLine = call.int("startLine")
        let endLine = call.int("endLine")
        let url = try resolveFileReadingPath(raw, in: s)
        let rel = fileReadingRelativePath(of: url, in: s)
        let root = Self.folder(of: s.model)
        // Legacy runs porcelain first (its failure is the tool's
        // failure), then `blame -s` for the readable snippet. The
        // `-L` range rules differ between the two runs, preserved
        // here: porcelain also takes a lone start line (start,
        // start+30); the readable run only takes a full range.
        var args = ["blame", "--porcelain"]
        if let start = startLine, let end = endLine, start > 0, end >= start {
            args += ["-L", "\(start),\(end)"]
        } else if let start = startLine, start > 0 {
            args += ["-L", "\(start),\(start + 30)"]
        }
        args += ["--", rel]
        let porcelain = try Self.runGit(args, in: root)
        guard porcelain.status == 0 else {
            throw MCPToolError("git blame failed: \(porcelain.combined)")
        }
        var formatArgs = ["blame", "-s"]
        if let start = startLine, let end = endLine, start > 0, end >= start {
            formatArgs += ["-L", "\(start),\(end)"]
        }
        formatArgs += ["--", rel]
        // Legacy ignores a failure of the readable run (`try?`): the
        // porcelain run above already decided success or failure.
        let readable = (try? Self.runGit(formatArgs, in: root))?.stdout ?? ""
        let lines = readable.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return .text("Git blame for `\(raw)`:\n\n" + lines.prefix(50).joined(separator: "\n"))
    }

    func gitBranchCompare(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let baseRaw = call.arguments["base"]?.string else { throw MCPToolError("Missing required parameter: base") }
        guard let headRaw = call.arguments["head"]?.string else { throw MCPToolError("Missing required parameter: head") }
        let base = baseRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = headRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw MCPToolError("Missing required parameter: base") }
        guard !head.isEmpty else { throw MCPToolError("Missing required parameter: head") }
        guard Self.gitIsValidRef(base) else { throw MCPToolError("Invalid git ref for base: \(base)") }
        guard Self.gitIsValidRef(head) else { throw MCPToolError("Invalid git ref for head: \(head)") }
        let root = Self.folder(of: s.model)
        let logResult = try Self.runGit(["log", "--oneline", "\(base)..\(head)"], in: root)
        guard logResult.status == 0 else {
            throw MCPToolError("Git log failed for \(base)..\(head): \(logResult.combined.isEmpty ? "unknown error" : logResult.combined)")
        }
        let statResult = try Self.runGit(["diff", "--stat", "\(base)...\(head)"], in: root)
        guard statResult.status == 0 else {
            throw MCPToolError("Git diff failed for \(base)...\(head): \(statResult.combined.isEmpty ? "unknown error" : statResult.combined)")
        }
        let commits = logResult.combined
        let commitLines = commits.isEmpty ? [] : commits.components(separatedBy: "\n")
        let stat = statResult.combined
        let commitSection = commitLines.isEmpty ? "No commits in \(head) not in \(base)." : commitLines.joined(separator: "\n")
        let statSection = stat.isEmpty ? "No differences." : stat
        let output = "Branch comparison \(base)...\(head)\n\nCommits in \(head) not in \(base) (\(commitLines.count)):\n\(commitSection)\n\nDiff stat:\n\(statSection)"
        return .structured(["base": .string(base), "head": .string(head), "commits": .string(commits),
                            "diffStat": .string(stat), "commitCount": .int(commitLines.count)],
                           summary: output)
    }

    func gitBranchManager(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let actionRaw = call.arguments["action"]?.string else { throw MCPToolError("Missing required parameter: action") }
        let action = actionRaw.lowercased()
        let branchName = call.arguments["branchName"]?.string ?? ""
        var gitArgs: [String] = []
        var mutating = false
        switch action {
        case "list", "branches":
            gitArgs = ["branch", "-a"]
        case "current":
            gitArgs = ["branch", "--show-current"]
        case "create":
            guard !branchName.isEmpty else { throw MCPToolError("Action 'create' requires 'branchName'.") }
            guard Self.gitIsValidRefName(branchName) else { throw MCPToolError("Invalid branch name: \(branchName)") }
            // Legacy creates with `checkout -b`: the branch is created
            // AND checked out.
            gitArgs = ["checkout", "-b", branchName]
            mutating = true
        case "switch", "checkout":
            guard !branchName.isEmpty else { throw MCPToolError("Action 'switch' requires 'branchName'.") }
            guard Self.gitIsValidRefName(branchName) else { throw MCPToolError("Invalid branch name: \(branchName)") }
            gitArgs = ["checkout", branchName]
            mutating = true
        case "delete":
            guard !branchName.isEmpty else { throw MCPToolError("Action 'delete' requires 'branchName'.") }
            guard Self.gitIsValidRefName(branchName) else { throw MCPToolError("Invalid branch name: \(branchName)") }
            // Safe delete (`-d`): refuses an unmerged branch, as Legacy does.
            gitArgs = ["branch", "-d", branchName]
            mutating = true
        default:
            throw MCPToolError("Unsupported action '\(actionRaw)'. Supported: list, current, create, switch, delete.")
        }
        if mutating {
            try await gitApproveChange(tool: call.name, summary: "Git branch \(action)\(branchName.isEmpty ? "" : " \(branchName)")", in: s, call: call)
        }
        let root = Self.folder(of: s.model)
        let result = try Self.runGit(gitArgs, in: root)
        let out = result.combined
        guard result.status == 0 else {
            throw MCPToolError("Git branch operation failed: \(out)")
        }
        return .text(out.isEmpty ? "Branch operation '\(actionRaw)' succeeded." : out)
    }
}

extension YcodeMCPHost {
    // MARK: - Git tool handlers (continued)

    func gitCherryPick(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let commitRaw = call.arguments["commit"]?.string else { throw MCPToolError("Missing required parameter: commit") }
        let commit = commitRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commit.isEmpty else { throw MCPToolError("Missing required parameter: commit") }
        guard Self.gitIsValidCommit(commit) else { throw MCPToolError("Invalid commit: \(commit)") }
        var args = ["cherry-pick"]
        if Self.gitBoolValue(call.arguments["noCommit"]) { args.append("--no-commit") }
        args.append(commit)
        try await gitApproveChange(tool: call.name, summary: "Cherry-pick \(commit)\(args.contains("--no-commit") ? " (--no-commit)" : "")", in: s, call: call)
        let root = Self.folder(of: s.model)
        let result = try Self.runGit(args, in: root)
        let output = result.combined
        guard result.status == 0 else {
            let conflicted = gitCherryPickConflictedFiles(in: root)
            if !conflicted.isEmpty {
                throw MCPToolError("Cherry-pick of \(commit) stopped due to conflicts in: \(conflicted.joined(separator: ", ")). Resolve the conflicts and commit, or run git cherry-pick --abort. Git output: \(output)")
            }
            throw MCPToolError("Git cherry-pick failed: \(output.isEmpty ? "unknown error" : output)")
        }
        let display = output.isEmpty ? "Cherry-pick completed with no output." : output
        return .structured(["commit": .string(commit), "output": .string(output)],
                           summary: "Cherry-picked \(commit).\n\(display)")
    }

    /// The conflicted files of a stopped cherry-pick, from
    /// `git status --porcelain` (Legacy's `conflictedFiles`): the
    /// two-letter codes for unmerged paths.
    nonisolated static func gitCherryPickConflictedFiles(in root: URL) -> [String] {
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

    func gitConflictResolver(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let resolution = (call.arguments["resolution"]?.string ?? "inspect").lowercased()
        let url = try resolveFileReadingPath(raw, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("File not found at path: \(raw)")
        }
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Unable to read content of file at \(raw)")
        }
        guard content.contains("<<<<<<<") && content.contains("=======") && content.contains(">>>>>>>") else {
            return .text("No active Git conflict markers (<<<<<<< / ======= / >>>>>>>) found in \(raw).")
        }
        if resolution == "inspect" {
            var conflicts: [String] = []
            let lines = content.components(separatedBy: .newlines)
            var inConflict = false
            var currentBlock: [String] = []
            for line in lines {
                if line.hasPrefix("<<<<<<<") {
                    inConflict = true
                    currentBlock = [line]
                } else if line.hasPrefix(">>>>>>>"), inConflict {
                    currentBlock.append(line)
                    conflicts.append(currentBlock.joined(separator: "\n"))
                    inConflict = false
                    currentBlock = []
                } else if inConflict {
                    currentBlock.append(line)
                }
            }
            var report = "### Detected \(conflicts.count) Merge Conflict(s) in `\(raw)`:\n\n"
            for (index, block) in conflicts.enumerated() {
                report += "#### Conflict #\(index + 1):\n```\n\(block)\n```\n\n"
            }
            report += "Use resolution: 'take_ours' or 'take_theirs', or code_replace to resolve precisely."
            return .text(report)
        }
        guard resolution == "take_ours" || resolution == "take_theirs" else {
            throw MCPToolError("Unknown resolution '\(resolution)'. Use 'inspect', 'take_ours', or 'take_theirs'.")
        }
        // The state machine from Legacy: marker lines are dropped, and
        // only the chosen side's lines survive.
        enum ConflictState { case normal, inOurs, inTheirs }
        var resolvedLines: [String] = []
        var state: ConflictState = .normal
        for line in content.components(separatedBy: .newlines) {
            if line.hasPrefix("<<<<<<<") {
                state = .inOurs
            } else if line.hasPrefix("======="), state == .inOurs {
                state = .inTheirs
            } else if line.hasPrefix(">>>>>>>"), state == .inTheirs || state == .inOurs {
                state = .normal
            } else {
                switch state {
                case .normal:
                    resolvedLines.append(line)
                case .inOurs:
                    if resolution == "take_ours" { resolvedLines.append(line) }
                case .inTheirs:
                    if resolution == "take_theirs" { resolvedLines.append(line) }
                }
            }
        }
        let resolvedText = resolvedLines.joined(separator: "\n")
        let rel = fileReadingRelativePath(of: url, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: content, proposed: resolvedText,
                                   summary: "Resolve conflicts in \(rel) (\(resolution))"), call: call, session: s)
        return .text("Successfully resolved all conflict markers in `\(raw)` using '\(resolution)'.")
    }

    func gitLogViewer(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let maxCount = call.int("maxCount") ?? 15
        let root = Self.folder(of: s.model)
        var args = ["log", "-n", "\(maxCount)", "--pretty=format:%h | %an | %ad | %s", "--date=short"]
        if let pathRaw = call.arguments["path"]?.string, !pathRaw.isEmpty {
            let url = try resolveFileReadingPath(pathRaw, in: s)
            args += ["--", fileReadingRelativePath(of: url, in: s)]
        }
        let result = try Self.runGit(args, in: root)
        let out = result.combined
        guard result.status == 0 else {
            throw MCPToolError("git log failed: \(out)")
        }
        guard !out.isEmpty else {
            return .text("No commits found in the repository history.")
        }
        let lines = out.components(separatedBy: .newlines)
        var report = "### Recent Git Commits (\(lines.count) entries):\n\n"
        for line in lines { report += "- `\(line)`\n" }
        return .text(report)
    }

    func gitPRSummary(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let baseRaw = call.arguments["base"]?.string ?? "main"
        let headRaw = call.arguments["head"]?.string ?? "HEAD"
        let base = baseRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = headRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw MCPToolError("Base ref must not be empty.") }
        guard !head.isEmpty else { throw MCPToolError("Head ref must not be empty.") }
        guard Self.gitIsValidRef(base) else { throw MCPToolError("Invalid git ref for base: \(base)") }
        guard Self.gitIsValidRef(head) else { throw MCPToolError("Invalid git ref for head: \(head)") }
        let root = Self.folder(of: s.model)
        let logResult = try Self.runGit(["log", "--oneline", "\(base)..\(head)"], in: root)
        guard logResult.status == 0 else {
            throw MCPToolError("Git log failed for \(base)..\(head): \(logResult.combined.isEmpty ? "unknown error" : logResult.combined)")
        }
        let statResult = try Self.runGit(["diff", "--stat", "\(base)...\(head)"], in: root)
        guard statResult.status == 0 else {
            throw MCPToolError("Git diff failed for \(base)...\(head): \(statResult.combined.isEmpty ? "unknown error" : statResult.combined)")
        }
        let shortStatResult = try Self.runGit(["diff", "--shortstat", "\(base)...\(head)"], in: root)
        let shortStat = shortStatResult.status == 0 ? shortStatResult.combined : ""
        let namesResult = try Self.runGit(["diff", "--name-only", "\(base)...\(head)"], in: root)
        let changedFiles = namesResult.status == 0 ? namesResult.combined : ""
        let commits = logResult.combined
        let commitLines = commits.isEmpty ? [] : commits.components(separatedBy: "\n")
        let fileLines = changedFiles.isEmpty ? [] : changedFiles.components(separatedBy: "\n")
        let filesChanged = Self.gitNumberBefore("file", in: shortStat)
        let insertions = Self.gitNumberBefore("insertion", in: shortStat)
        let deletions = Self.gitNumberBefore("deletion", in: shortStat)
        let fileCount = fileLines.isEmpty ? filesChanged : fileLines.count
        var lines: [String] = []
        lines.append("# PR Summary")
        lines.append("")
        lines.append("Base: `\(base)` → Head: `\(head)`")
        lines.append("")
        lines.append("## Commits (\(commitLines.count))")
        if commitLines.isEmpty {
            lines.append("No commits in \(head) not in \(base).")
        } else {
            for commit in commitLines { lines.append("- \(commit)") }
        }
        lines.append("")
        lines.append("## Files changed (\(fileCount))")
        if fileLines.isEmpty {
            lines.append("No files changed.")
        } else {
            for file in fileLines { lines.append("- `\(file)`") }
        }
        lines.append("")
        lines.append("## Stats")
        if shortStat.isEmpty {
            lines.append("No changes.")
        } else {
            lines.append(shortStat)
        }
        lines.append("")
        lines.append("Files changed: \(fileCount) | Insertions: \(insertions) | Deletions: \(deletions)")
        let summary = lines.joined(separator: "\n")
        return .structured(["summary": .string(summary), "base": .string(base), "head": .string(head),
                            "commitCount": .int(commitLines.count), "fileCount": .int(fileCount),
                            "insertions": .int(insertions), "deletions": .int(deletions),
                            "shortstat": .string(shortStat)],
                           summary: summary)
    }

    func gitStashOperator(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let actionRaw = call.arguments["action"]?.string else { throw MCPToolError("Missing required parameter: action") }
        let action = actionRaw.lowercased()
        let message = call.arguments["message"]?.string
        let stashIndex = call.arguments["stashIndex"]?.string ?? "stash@{0}"
        var arguments = ["stash"]
        var mutating = false
        switch action {
        case "save", "push":
            arguments.append("push")
            if let msg = message, !msg.isEmpty {
                arguments.append("-m")
                arguments.append(msg)
            }
            mutating = true
        case "pop":
            guard Self.gitIsValidStashRef(stashIndex) else { throw MCPToolError("Invalid stash identifier: \(stashIndex)") }
            arguments.append("pop")
            arguments.append(stashIndex)
            mutating = true
        case "list":
            arguments.append("list")
        case "show":
            guard Self.gitIsValidStashRef(stashIndex) else { throw MCPToolError("Invalid stash identifier: \(stashIndex)") }
            arguments.append("show")
            arguments.append("-p")
            arguments.append(stashIndex)
        case "drop":
            guard Self.gitIsValidStashRef(stashIndex) else { throw MCPToolError("Invalid stash identifier: \(stashIndex)") }
            arguments.append("drop")
            arguments.append(stashIndex)
            mutating = true
        default:
            throw MCPToolError("Unsupported action '\(actionRaw)'. Valid: save, pop, list, show, drop")
        }
        if mutating {
            try await gitApproveChange(tool: call.name, summary: "Git stash \(action)\((action == "save" || action == "push") && message != nil ? " \"\(message!)\"" : "")", in: s, call: call)
        }
        let root = Self.folder(of: s.model)
        let result = try Self.runGit(arguments, in: root)
        guard result.status == 0 else {
            throw MCPToolError("Git stash \(actionRaw) failed (exit \(result.status)):\n\(result.stderr)\n\(result.stdout)")
        }
        // Legacy prefers stdout, then stderr, then a completion message.
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty { return .text(result.stdout) }
        if !stderr.isEmpty { return .text(result.stderr) }
        return .text("Git stash \(actionRaw) completed.")
    }

    func gitHubRepo(_ call: MCPToolCall) async throws -> MCPToolResult {
        // Honestly failing: Ycode's MCP host has no GitHub API client
        // and no GitHub credential store, and this wave must not touch
        // remotes or GitHub. Legacy's tool reads live repositories
        // over the GitHub API (public repos unauthenticated, private
        // repos with the user's saved credential); none of that can
        // be reproduced here, and no GitHub data is faked. Remote /
        // GitHub access is a later wave.
        _ = try session(for: call)
        throw MCPToolError("github_repo needs a GitHub API client with authentication, which Ycode's MCP host does not have yet: no GitHub data was fetched. Remote and GitHub access is a later wave; use the workspace's local git tools (git_log_viewer, git_branch_compare, git_pr_summary) for local repository information.")
    }

    func recentChanges(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let hours = max(1, min(720, call.int("hours") ?? 24))
        let limit = max(1, min(500, call.int("limit") ?? 50))
        let root = Self.folder(of: s.model)
        let cutoff = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        var changed: [(String, Date)] = []
        for url in Self.gitScanFiles(under: root) {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate, date >= cutoff else { continue }
            changed.append((fileReadingRelativePath(of: url, in: s), date))
        }
        changed.sort { $0.1 > $1.1 }
        if changed.isEmpty {
            return .structured(["count": .int(0), "hours": .int(hours)],
                               summary: "No files modified in the last \(hours)h.")
        }
        var lines = ["Files modified in the last \(hours)h (\(changed.count) total):"]
        for (path, date) in changed.prefix(limit) {
            lines.append("- \(path) — \(Self.gitISO8601(date))")
        }
        if changed.count > limit {
            lines.append("… [truncated: showing \(limit) of \(changed.count)]")
        }
        return .structured(["count": .int(changed.count), "hours": .int(hours)],
                           summary: lines.joined(separator: "\n"))
    }

    func versionControlOperator(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let action = (call.arguments["action"]?.string ?? "status").lowercased()
        let root = Self.folder(of: s.model)
        switch action {
        case "status", "diff":
            // Read-only actions: no approval, but the tool is
            // registered `writes: true`, so the server still refuses
            // them in `readOnly` mode.
            let args = action == "status" ? ["status", "--short"] : ["diff", "--", "."]
            let result = try Self.runGit(args, in: root)
            guard result.status == 0 else {
                throw MCPToolError("Git \(action) failed: \(result.combined)")
            }
            return .structured(["output": .string(result.combined)], summary: "Git action executed: \(action)")
        case "commit":
            let message = call.arguments["message"]?.string ?? "Assist automated commit"
            try await gitApproveChange(tool: call.name, summary: "Git commit: \(message)", in: s, call: call)
            let staged = try Self.runGit(["add", "-A"], in: root)
            guard staged.status == 0 else {
                throw MCPToolError("Git commit failed: \(staged.combined)")
            }
            let result = try Self.runGit(["commit", "-m", message], in: root)
            guard result.status == 0 else {
                throw MCPToolError("Git commit failed: \(result.combined)")
            }
            return .structured(["output": .string(result.combined)], summary: "Git action executed: commit")
        case "branch":
            let name = call.arguments["name"]?.string ?? "assist/automation"
            guard Self.gitIsValidRefName(name) else { throw MCPToolError("Invalid branch name: \(name)") }
            try await gitApproveChange(tool: call.name, summary: "Git branch: create \(name)", in: s, call: call)
            let result = try Self.runGit(["checkout", "-b", name], in: root)
            guard result.status == 0 else {
                throw MCPToolError("Git branch checkout failed: \(result.combined)")
            }
            return .structured(["output": .string(result.combined)], summary: "Git action executed: branch")
        case "rollback":
            let ref = call.arguments["ref"]?.string ?? "HEAD~1"
            guard Self.gitIsValidRefName(ref) else { throw MCPToolError("Invalid git ref: \(ref)") }
            try await gitApproveChange(tool: call.name, summary: "Git rollback: reset --hard \(ref)", in: s, call: call)
            let result = try Self.runGit(["reset", "--hard", ref], in: root)
            guard result.status == 0 else {
                throw MCPToolError("Git rollback failed: \(result.combined)")
            }
            return .structured(["output": .string(result.combined)], summary: "Git action executed: rollback")
        case "push", "pull", "fetch", "clone":
            // Legacy implements no remote sub-operations at all; this
            // wave must not touch remotes. Rejected explicitly, naming
            // the later-wave prerequisite, instead of Legacy's generic
            // unknown-action error.
            throw MCPToolError("Git \(action) needs remote access, which is out of scope for this wave (local operations only). Remote operations (push/pull/fetch/clone) are a later wave.")
        default:
            throw MCPToolError("Unknown git action '\(action)': expected status, commit, branch, rollback, or diff.")
        }
    }
}
