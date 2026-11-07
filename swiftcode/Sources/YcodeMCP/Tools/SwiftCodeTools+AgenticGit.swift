import Foundation
import YcodeAssistant
import YcodeIDECore
import YcodeSubprocess

extension SwiftCodeMCPHost {
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
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace.")]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitPull(call)
            },
            tool("git_push", "Git Push",
                 "Pushes committed changes to the remote repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "repositoryPath": Schema.string("Repository path. Defaults to the workspace root when omitted; must stay inside the workspace.")]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticGitPush(call)
            },
            tool("git_clone", "Git Clone",
                 "Clones a Git repository.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "remoteURL": Schema.string("Remote repository URL to clone."),
                                       "destinationPath": Schema.string("Destination path for the clone.")],
                                      required: ["remoteURL", "destinationPath"]),
                 annotations: safeMutation, writes: true) { h, call in
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

extension SwiftCodeMCPHost {

    func agenticGitRepoDir(_ call: MCPToolCall, in s: WorkspaceSession) throws -> URL {
        guard let raw = call.string("repositoryPath") else { return Self.folder(of: s.model) }
        let url = try resolveFileReadingPath(raw, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("repositoryPath is not a directory: \(raw)")
        }
        return url
    }

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

    nonisolated static func agenticGitRun(_ args: [String], in root: URL, failure: String) throws -> String {
        let result = try Self.runGit(args, in: root)
        let output = result.combined
        guard result.status == 0 else {
            throw MCPToolError("\(failure): \(output.isEmpty ? "unknown error" : output)")
        }
        return output
    }

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

    nonisolated static func agenticGitSuccess(output: String, fallback: String) -> MCPToolResult {
        .text(output.isEmpty ? fallback : output)
    }

    nonisolated(unsafe) static var agenticGitTestSecretStore: SecretStore?

    nonisolated static func agenticGitSecretStore() -> SecretStore {
        agenticGitTestSecretStore ?? defaultSecretStore()
    }

    struct ValidatedGitRemoteURL: Sendable {
        var gitArgument: String
        var githubHTTPSPath: String?
    }

    nonisolated static func gitHubHTTPSPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://"), !trimmed.contains(" "),
              let components = URLComponents(string: trimmed),
              let host = components.host, host.lowercased() == "github.com",
              components.user == nil, components.password == nil else { return nil }
        let path = components.path
        guard !path.isEmpty, path != "/" else { return "" }
        return String(path.dropFirst())
    }

    func validateGitRemoteURL(_ raw: String, in s: WorkspaceSession) throws -> ValidatedGitRemoteURL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPToolError("Remote URL must not be empty.") }
        guard !trimmed.hasPrefix("-") else { throw MCPToolError("Invalid remote URL: \(trimmed)") }
        guard !trimmed.contains("\0"), !trimmed.contains("\n"), !trimmed.contains("\r") else {
            throw MCPToolError("Invalid remote URL.")
        }
        if trimmed.contains("://") {
            guard trimmed.hasPrefix("https://"), !trimmed.contains(" "),
                  let components = URLComponents(string: trimmed),
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil else {
                throw MCPToolError("Unsupported remote URL '\(trimmed)'. Only https:// URLs, git@host: SSH remotes, and local paths inside the workspace are allowed; URLs must not contain embedded credentials.")
            }
            return ValidatedGitRemoteURL(gitArgument: trimmed,
                                         githubHTTPSPath: Self.gitHubHTTPSPath(trimmed))
        }
        if !trimmed.hasPrefix("/"), !trimmed.hasPrefix("."), !trimmed.hasPrefix("~"),
           let at = trimmed.firstIndex(of: "@"), let colon = trimmed.firstIndex(of: ":"),
           at < colon {
            let user = String(trimmed[..<at])
            let host = String(trimmed[trimmed.index(after: at)..<colon])
            let path = String(trimmed[trimmed.index(after: colon)...])
            let plain = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
            if !user.isEmpty, !host.isEmpty, !path.isEmpty,
               user.unicodeScalars.allSatisfy({ plain.contains($0) }),
               host.unicodeScalars.allSatisfy({ plain.contains($0) }),
               !path.contains(" "), !path.contains("\t") {
                return ValidatedGitRemoteURL(gitArgument: trimmed, githubHTTPSPath: nil)
            }
        }
        let url = try resolveFileReadingPath(trimmed, in: s)
        return ValidatedGitRemoteURL(gitArgument: url.path, githubHTTPSPath: nil)
    }

    nonisolated static func seedGitHubCredential(githubHTTPSPath path: String?, in directory: URL) {
        guard let path,
              let token = agenticGitSecretStore().readString(SecretAccount.githubToken)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return }
        var lines = ["protocol=https", "host=github.com"]
        if !path.isEmpty { lines.append("path=\(path)") }
        lines.append("username=x-access-token")
        lines.append("password=\(token)")
        let input = lines.joined(separator: "\n") + "\n\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: HostTool.path("git"))
        process.arguments = ["credential", "approve"]
        process.environment = gitEnvironment()
        process.currentDirectoryURL = directory
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try stdin.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    nonisolated static func seedGitHubCredentialForOrigin(in root: URL) {
        guard let result = try? runGit(["remote", "get-url", "origin"], in: root), result.status == 0 else { return }
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        seedGitHubCredential(githubHTTPSPath: gitHubHTTPSPath(url), in: root)
    }
}

extension SwiftCodeMCPHost {

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
        if action != "list" && action != "show" {
            try await gitApproveChange(tool: call.name, summary: "Git stash \(action)", in: s, call: call)
        }
        let output = try Self.agenticGitRun(["stash", action], in: root, failure: "Git stash \(action) failed")
        return Self.agenticGitSuccess(output: output, fallback: "Successfully executed git stash \(action)")
    }

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
        if action != "list" && action != "prune" {
            try await gitApproveChange(tool: call.name, summary: "Git worktree \(action)", in: s, call: call)
        }
        let output = try Self.agenticGitRun(["worktree", action], in: root, failure: "Git worktree \(action) failed")
        return Self.agenticGitSuccess(output: output, fallback: "Git worktree \(action) completed.")
    }

    func agenticGitPull(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        try await gitApproveChange(tool: call.name, summary: "Git pull", in: s, call: call)
        Self.seedGitHubCredentialForOrigin(in: root)
        let output = try Self.agenticGitRun(["pull"], in: root, failure: "Git pull failed")
        return .structured(["output": .string(output)], summary: "Successfully pulled changes")
    }

    func agenticGitPush(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = try agenticGitRepoDir(call, in: s)
        try await gitApproveChange(tool: call.name, summary: "Git push", in: s, call: call)
        Self.seedGitHubCredentialForOrigin(in: root)
        let output = try Self.agenticGitRun(["push"], in: root, failure: "Git push failed")
        return .structured(["output": .string(output)], summary: "Push successful")
    }

    func agenticGitClone(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let remoteURL = call.string("remoteURL"),
              let destinationRaw = call.string("destinationPath") else {
            throw MCPToolError("Missing remoteURL or destinationPath")
        }
        let remote = try validateGitRemoteURL(remoteURL, in: s)
        let destination = try resolveFileReadingPath(destinationRaw, in: s)
        try await gitApproveChange(tool: call.name, summary: "Git clone \(remoteURL)", in: s, call: call)
        Self.seedGitHubCredential(githubHTTPSPath: remote.githubHTTPSPath, in: Self.folder(of: s.model))
        let output = try Self.agenticGitRun(["clone", remote.gitArgument, destination.path],
                                            in: Self.folder(of: s.model), failure: "Git clone failed")
        return .structured(["output": .string(output)],
                           summary: "Successfully cloned \(remoteURL) to \(destinationRaw)")
    }
}
