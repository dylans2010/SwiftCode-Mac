import Foundation

// MARK: - SDKSourceControlAdapter
//
// THE ONLY SOURCE-CONTROL PATH EXTENSIONS MAY USE (spec §8.5, §11.1/§11.2).
//
// This adapter is the single host-owned bridge between the SDK surface and
// the real `GitService`. It exposes READS ONLY — `getStatus` and `getDiff`
// (plus the broker-exempt `isRepository` probe used by host UI). It never
// calls and never exposes stage / commit / checkout / push / rollback or any
// other `GitService` mutation: those methods are unreachable from here BY
// CONSTRUCTION — no code path in this file references them, and the SDK IPC
// surface must never vend this actor to extension code directly.
//
// Authorization: every extension-facing method authorizes FIRST via
// `SDKCapabilityBroker.authorize(.sourceControlRead, for:)` on every call.
// `isRepository(at:)` is the deliberate exception (no broker check): it is
// also used by host-owned UI that has no extension identity.
//
// Read-only guarantees beyond the capability gate:
// - Absolute filesystem paths are NEVER emitted. Every path that crosses
//   this boundary is rewritten repository-relative (the project-root prefix
//   is stripped; anything that cannot be relativized degrades to a bare
//   filename), so an extension cannot learn the host's directory layout.
// - Diffs are byte-bounded (`SDKDiffOptions.maxBytes`, default 256 KiB).
//   Oversized output is TRUNCATED WITH METADATA (`truncated` flags,
//   `totalBytes`, `byteLimit`) — never silently cut, and never rejected
//   with `outputTooLarge`. That code is reserved in the taxonomy but this
//   adapter does not throw it: a bounded diff with explicit truncation
//   metadata is what the spec (§11.2) requires.
// - Binary files are never inlined: per the contract they appear with empty
//   `hunks` and `truncated = true`.
// - Error messages are passed through `SDKLogRedaction.sanitizeForUser` and
//   truncated to 300 characters; absolute paths and tokens never leak.
//
// Known honest limitations (see agent_notes.md for detail):
// - `GitService.getDiff` runs a plain `git diff` (unstaged, tracked working
//   tree) and its parser discards the `diff --git` file headers, so this
//   adapter reconstructs per-file boundaries from the residual header lines
//   embedded in hunk tails. The first file's header never survives the
//   parser, so a positional `git diff --name-only` fallback (same ordering,
//   applied only when counts match) repairs it; unrepaired paths stay the
//   literal "unknown" rather than a guessed path.
// - `SDKDiffOptions.includeUntracked` is accepted for forward compatibility
//   but the underlying service cannot supply untracked content yet.
// - `SDKDiffOptions.paths`: absolute paths and `..` segments are rejected
//   with INVALID_ARGUMENT; any other non-empty filter is rejected with
//   INVALID_ARGUMENT because the service cannot honor it — silently
//   ignoring a scope filter would hand back MORE data than requested.

public actor SDKSourceControlAdapter {

    public static let shared = SDKSourceControlAdapter()

    private init() {}

    // MARK: - Repository probe (no broker check; host UI uses this too)

    /// True when `projectRoot` is inside a git working tree. Runs
    /// `git rev-parse --is-inside-work-tree` and returns true only on exit 0
    /// with stdout trimming to "true". Never throws; any failure is false.
    public func isRepository(at projectRoot: URL) async -> Bool {
        guard let result = try? await ProcessRunnerTool.shared.run(
            executableURL: await gitExecutableURL(),
            arguments: ["rev-parse", "--is-inside-work-tree"],
            workingDirectory: projectRoot
        ) else {
            return false
        }
        return result.exitCode == 0
            && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    // MARK: - Status (read-only)

    /// Repository status snapshot for the caller's project. Authorizes
    /// `.sourceControlRead` first. When the project is not a repository,
    /// returns the contract's empty shape (`isRepository: false`) rather
    /// than throwing — status is a query (contract §11.2).
    public func getStatus(caller: SDKCallerIdentity) async throws -> SDKRepositoryStatus {
        try await SDKCapabilityBroker.authorize(.sourceControlRead, for: caller)

        let projectRoot = URL(
            fileURLWithPath: caller.projectRootPath,
            isDirectory: true
        ).standardized

        guard await isRepository(at: projectRoot) else {
            return SDKRepositoryStatus(isRepository: false)
        }

        do {
            let snapshot = try await withTimeout(seconds: 30) {
                try await GitService.shared.getStatus(for: projectRoot)
            }
            return mapStatus(snapshot, root: projectRoot)
        } catch let appError as AppError {
            throw mapGitError(appError)
        }
    }

    // MARK: - Diff (read-only, byte-bounded)

    /// Bounded unified diff of the working tree. Authorizes
    /// `.sourceControlRead` first, then races the real `GitService.getDiff`
    /// against a 60 s timeout. Unlike status, diff REQUIRES a repository:
    /// a non-repository surfaces as typed `.notARepository`.
    public func getDiff(
        caller: SDKCallerIdentity,
        options: SDKDiffOptions
    ) async throws -> SDKRepositoryDiff {
        try await SDKCapabilityBroker.authorize(.sourceControlRead, for: caller)

        let projectRoot = URL(
            fileURLWithPath: caller.projectRootPath,
            isDirectory: true
        ).standardized

        try validateDiffPaths(options.paths)

        do {
            let (hunks, pathOrder) = try await withTimeout(seconds: 60) {
                async let diffHunks = GitService.shared.getDiff(repositoryURL: projectRoot)
                async let nameOrder = self.diffPathOrder(root: projectRoot)
                return try await (diffHunks, nameOrder)
            }
            return assembleDiff(from: hunks, maxBytes: options.maxBytes, pathOrderFallback: pathOrder)
        } catch let appError as AppError {
            throw mapGitError(appError)
        }
    }

    // MARK: - Status mapping

    private func mapStatus(_ snapshot: GitStatusSnapshot, root: URL) -> SDKRepositoryStatus {
        let files = snapshot.files.map { file in
            SDKFileChangeSummary(
                path: repoRelativePath(file.path, root: root),
                status: mapFileStatus(file.status),
                isStaged: file.isStaged
            )
        }
        let stagedCount = snapshot.files.filter { $0.isStaged }.count
        let untrackedCount = snapshot.files.filter { $0.status == .untracked }.count
        let unstagedCount = snapshot.files.filter {
            !$0.isStaged && $0.status != .untracked
        }.count

        let rawBranch = snapshot.branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let branchName: String? =
            (rawBranch.isEmpty || rawBranch.caseInsensitiveCompare("unknown") == .orderedSame)
            ? nil : rawBranch

        return SDKRepositoryStatus(
            isRepository: true,
            branchName: branchName,
            ahead: snapshot.ahead,
            behind: snapshot.behind,
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount,
            files: files
        )
    }

    private func mapFileStatus(_ status: GitFileStatus.Status) -> SDKFileChangeStatus {
        switch status {
        case .modified: return .modified
        case .added: return .added
        case .deleted: return .deleted
        case .renamed: return .renamed
        case .untracked: return .untracked
        case .conflicted: return .conflicted
        }
    }

    /// Rewrites an absolute file URL to a repository-relative path. Never
    /// returns an absolute path: anything that cannot be relativized
    /// degrades to the bare filename.
    private func repoRelativePath(_ fileURL: URL, root: URL) -> String {
        let rootPath = root.path
        let path = fileURL.standardized.path
        if path == rootPath {
            return fileURL.lastPathComponent
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }

    // MARK: - Diff assembly (bounded)

    private struct RawFileDiff {
        var path: String
        var chunks: [String] = []
        var isBinary = false
    }

    /// Reassembles per-file diffs from `[GitDiffHunk]`, applies the byte
    /// budget, and returns the bounded `SDKRepositoryDiff`.
    ///
    /// `GitService`'s parser splits on `@@ ` hunk headers and drops the
    /// `diff --git` file headers, so file boundaries are reconstructed here
    /// from the residual `diff --git a/… b/…` lines that land in hunk tails.
    /// A `Binary files … differ` line marks the current file binary instead
    /// of contributing content. This is deterministic post-processing of
    /// real service output — no re-parsing of git, no guessing.
    ///
    /// Budget semantics: files are emitted in order while they fit. The
    /// first file that would exceed the budget is emitted partially (cut at
    /// a UTF-8 character boundary), flagged `truncated`, and emission stops.
    /// `truncated` on the result is then true. The diff is NEVER rejected
    /// with `outputTooLarge` — truncation metadata is the specified
    /// behavior, so that error code stays unused by this adapter.
    ///
    /// - Parameter pathOrderFallback: positional file list from
    ///   `git diff --name-only`, used ONLY to repair paths the parser
    ///   dropped (the first file's `diff --git` header never survives
    ///   `GitService.parseDiff`). Applied positionally and only when the
    ///   counts match; otherwise "unknown" paths are kept as-is.
    private func assembleDiff(
        from hunks: [GitDiffHunk],
        maxBytes: Int,
        pathOrderFallback: [String]
    ) -> SDKRepositoryDiff {
        // 1. Regroup the flat hunk stream into per-file raw diffs.
        var rawFiles: [RawFileDiff] = []
        var current: RawFileDiff? = nil
        func flush() {
            if let file = current { rawFiles.append(file) }
            current = nil
        }
        for hunk in hunks {
            for line in [hunk.header] + hunk.lines {
                if line.hasPrefix("diff --git ") {
                    flush()
                    current = RawFileDiff(path: parseDiffGitPath(line) ?? "unknown")
                } else if line.hasPrefix("Binary files ") {
                    if current == nil { current = RawFileDiff(path: "unknown") }
                    current?.isBinary = true
                } else {
                    if current == nil { current = RawFileDiff(path: "unknown") }
                    current?.chunks.append(line)
                }
            }
        }
        flush()

        // 1b. Repair parser-dropped paths (the first file's header).
        if pathOrderFallback.count == rawFiles.count {
            for index in rawFiles.indices where rawFiles[index].path == "unknown" {
                rawFiles[index].path = pathOrderFallback[index]
            }
        }

        // 2. Split each file's chunks into hunk texts and measure bytes.
        struct BuiltFile {
            let path: String
            let hunkTexts: [String]
            let isBinary: Bool
            let byteCount: Int
        }
        let built: [BuiltFile] = rawFiles.map { raw in
            if raw.isBinary {
                // Contract: binary files are never inlined — empty hunks,
                // truncated = true. They contribute 0 inlined bytes.
                return BuiltFile(path: raw.path, hunkTexts: [], isBinary: true, byteCount: 0)
            }
            var hunkTexts: [String] = []
            var pending: [String] = []
            for line in raw.chunks {
                if line.hasPrefix("@@ ") && !pending.isEmpty {
                    hunkTexts.append(pending.joined(separator: "\n"))
                    pending = []
                }
                pending.append(line)
            }
            if !pending.isEmpty {
                hunkTexts.append(pending.joined(separator: "\n"))
            }
            let byteCount = hunkTexts.reduce(0) { $0 + $1.utf8.count }
            return BuiltFile(path: raw.path, hunkTexts: hunkTexts, isBinary: false, byteCount: byteCount)
        }

        let totalBytes = built.reduce(0) { $0 + $1.byteCount }

        // 3. Emit within the budget.
        var emitted: [SDKFileDiff] = []
        var usedBytes = 0
        var truncated = false
        for file in built {
            if usedBytes + file.byteCount <= maxBytes {
                emitted.append(SDKFileDiff(
                    path: file.path,
                    hunks: file.hunkTexts,
                    truncated: file.isBinary
                ))
                usedBytes += file.byteCount
                if file.isBinary { truncated = true }
                continue
            }
            // Budget exceeded mid-file: emit a character-boundary prefix.
            var kept: [String] = []
            var keptBytes = 0
            for hunkText in file.hunkTexts {
                let remaining = maxBytes - usedBytes - keptBytes
                guard remaining > 0 else { break }
                let hunkBytes = hunkText.utf8.count
                if keptBytes + hunkBytes <= remaining {
                    kept.append(hunkText)
                    keptBytes += hunkBytes
                } else {
                    let piece = bytePrefix(hunkText, limit: remaining - keptBytes)
                    if !piece.isEmpty {
                        kept.append(piece)
                        keptBytes += piece.utf8.count
                    }
                    break
                }
            }
            emitted.append(SDKFileDiff(path: file.path, hunks: kept, truncated: true))
            usedBytes += keptBytes
            truncated = true
            break
        }

        return SDKRepositoryDiff(
            files: emitted,
            truncated: truncated,
            totalBytes: totalBytes,
            byteLimit: maxBytes
        )
    }

    /// Parses `diff --git a/<old> b/<new>` → the new (b-side) path.
    /// Handles git's quoted form (`"b/pa th"`). Returns nil when unparseable.
    private func parseDiffGitPath(_ line: String) -> String? {
        let rest = String(line.dropFirst("diff --git ".count))
        if let range = rest.range(of: " b/", options: .backwards) {
            var path = String(rest[range.upperBound...])
            if path.hasPrefix("\"") && path.hasSuffix("\"") && path.count >= 2 {
                path = String(path.dropFirst().dropLast())
            }
            return path.isEmpty ? nil : path
        }
        // Fallback: last whitespace token with a b/ prefix stripped.
        if let token = rest.split(separator: " ").last.map(String.init) {
            let stripped = token.hasPrefix("b/") ? String(token.dropFirst(2)) : token
            return stripped.isEmpty ? nil : stripped
        }
        return nil
    }

    /// Longest prefix of `text` fitting in `limit` UTF-8 bytes, cut only at
    /// character boundaries (never splits a multi-byte scalar).
    private func bytePrefix(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        var bytes = 0
        var result = ""
        result.reserveCapacity(min(limit, text.utf8.count))
        for character in text {
            let charBytes = String(character).utf8.count
            if bytes + charBytes > limit { break }
            bytes += charBytes
            result.append(character)
        }
        return result
    }

    // MARK: - Diff option validation

    /// Absolute paths and `..` segments are rejected per the contract.
    /// Any other non-empty filter is rejected too: the underlying service
    /// cannot honor path filtering, and silently ignoring a scope filter
    /// would return MORE data than the extension asked for.
    private func validateDiffPaths(_ paths: [String]?) throws {
        guard let paths, !paths.isEmpty else { return }
        for path in paths {
            if path.hasPrefix("/") || path.split(separator: "/").contains("..") {
                throw SDKError(
                    code: .invalidArgument,
                    message: "Diff path filters must be repository-relative paths without '..' segments.",
                    suggestion: "Pass paths like \"Sources/App.swift\"."
                )
            }
        }
        throw SDKError(
            code: .invalidArgument,
            message: "Path-filtered diffs are not supported by the host yet.",
            suggestion: "Omit the paths filter to diff the whole repository."
        )
    }

    // MARK: - Timeout

    /// Races `operation` against a sleep; the loser is cancelled. On expiry
    /// throws typed `.requestTimeout`. The operation is a real call against
    /// `GitService` — not a mock, not a stub.
    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw SDKError(
                    code: .requestTimeout,
                    message: "The source-control request took longer than \(seconds) seconds.",
                    suggestion: "Try again; the repository may be unusually large or busy."
                )
            }
            guard let result = try await group.next() else {
                throw SDKError(
                    code: .requestTimeout,
                    message: "The source-control request produced no result.",
                    suggestion: "Try again."
                )
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Error mapping

    /// Maps `AppError.gitError` to typed `SDKError`s. `SDKError`s from the
    /// broker (permission denials etc.) pass through untouched — this catch
    /// only ever sees `AppError`.
    private func mapGitError(_ error: AppError) -> SDKError {
        guard case .gitError(let stderr) = error else {
            return SDKError(
                code: .serviceUnavailable,
                message: "Source control is temporarily unavailable.",
                suggestion: "Try again in a moment."
            )
        }
        let lowered = stderr.lowercased()

        if lowered.contains("not a git repository") {
            return SDKError(
                code: .notARepository,
                message: "This project is not inside a git repository.",
                suggestion: "Open a project that lives inside a git repository to use source-control features."
            )
        }

        let sanitized = String(
            SDKLogRedaction.sanitizeForUser(stderr).prefix(300)
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if lowered.contains("permission denied") {
            // Host-side filesystem problem, NOT an extension grant problem:
            // the capability was already authorized before git was invoked.
            return SDKError(
                code: .serviceUnavailable,
                message: "Source control hit a host filesystem permission problem (not an extension-permission problem).",
                suggestion: "Check that SwiftCode can read the repository directory, then try again.",
                diagnostics: sanitized.isEmpty ? nil : ["detail": sanitized]
            )
        }

        let message = sanitized.isEmpty
            ? "Git reported an error."
            : "Git reported an error: \(sanitized)"
        return SDKError(
            code: .serviceUnavailable,
            message: message,
            suggestion: "Try again; if it persists, check the repository in a terminal."
        )
    }

    // MARK: - Diff path-order fallback

    /// `git diff --name-only` in diff order, used ONLY to repair per-file
    /// paths that `GitService.parseDiff` drops (the first file's header).
    /// Nonisolated so it can run alongside the diff fetch inside the
    /// timeout race. Best-effort: empty on any failure, and the caller only
    /// applies it positionally when the counts match the regrouped files.
    private nonisolated func diffPathOrder(root: URL) async -> [String] {
        guard let result = try? await ProcessRunnerTool.shared.run(
            executableURL: await self.gitExecutableURL(),
            arguments: ["diff", "--name-only"],
            workingDirectory: root
        ), result.exitCode == 0 else {
            return []
        }
        return result.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { path in
                var p = path
                if p.hasPrefix("\"") && p.hasSuffix("\"") && p.count >= 2 {
                    p = String(p.dropFirst().dropLast())
                }
                return p
            }
    }

    // MARK: - Git executable lookup

    /// Mirrors `GitService`'s executable resolution (custom preference, then
    /// common install paths) because that lookup is private to `GitService`.
    /// If `GitService`'s resolution ever changes, revisit this.
    private func gitExecutableURL() async -> URL {
        if let customPath = await PreferencesStore.shared.get(forKey: "git_executable_path") as? String,
           !customPath.isEmpty {
            return URL(fileURLWithPath: customPath)
        }
        let commonPaths = [
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/usr/bin/git"
        ]
        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }
}
