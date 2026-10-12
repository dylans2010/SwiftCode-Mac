import Foundation

// MARK: - SDKFileChangeStatus
//
// Per-file change classification for repository status (spec §11.2).
// Values mirror the stable subset of git porcelain statuses.

public enum SDKFileChangeStatus: String, Codable, Sendable {
    /// Tracked file with unstaged or staged content modifications.
    case modified
    /// Newly staged file (added to the index).
    case added
    /// Tracked file deleted from the working tree and/or index.
    case deleted
    /// File renamed (old path → new path collapsed into `path`).
    case renamed
    /// Present in the working tree but not tracked by source control.
    case untracked
    /// File with unresolved merge conflicts.
    case conflicted
}

// MARK: - SDKFileChangeSummary
//
// One changed file in a repository status snapshot. `path` is always
// repository-RELATIVE (e.g. `Sources/App.swift`) — never absolute — so an
// extension cannot learn the host's directory layout beyond the repo root.

public struct SDKFileChangeSummary: Codable, Sendable {
    /// Repository-relative path. Never absolute (privacy).
    public let path: String
    /// What kind of change this file carries.
    public let status: SDKFileChangeStatus
    /// True when the change is staged in the index; false when it is
    /// working-tree-only. Untracked files are never staged.
    public let isStaged: Bool

    public init(path: String, status: SDKFileChangeStatus, isStaged: Bool) {
        self.path = path
        self.status = status
        self.isStaged = isStaged
    }
}

// MARK: - SDKRepositoryStatus
//
// Snapshot returned by `sourceControl.getStatus()` (spec §11.2).
// Contains only stable, necessary data: repository presence, branch,
// ahead/behind counts, and per-category file counts plus summaries.
//
// Semantics:
// - When `isRepository` is false, `branchName` is nil, all counts are 0,
//   and `files` is empty. The host reports NOT_A_REPOSITORY as a typed
//   `SDKError` only for operations that require a repository (e.g. diff);
//   status itself is a query and returns this empty shape.
// - `files` may be capped by the host; counts always reflect the true
//   totals even when the summary list is capped.

public struct SDKRepositoryStatus: Codable, Sendable {
    /// Whether the open project is inside a source-control repository.
    public let isRepository: Bool
    /// Current branch name when known; nil for detached HEAD or no repo.
    public let branchName: String?
    /// Commits the local branch is ahead of its upstream (0 if none/unknown).
    public let ahead: Int
    /// Commits the local branch is behind its upstream (0 if none/unknown).
    public let behind: Int
    /// Number of files with staged (index) changes.
    public let stagedCount: Int
    /// Number of files with unstaged (working tree) changes.
    public let unstagedCount: Int
    /// Number of untracked files.
    public let untrackedCount: Int
    /// Per-file summaries; paths are repository-relative, never absolute.
    public let files: [SDKFileChangeSummary]

    public init(
        isRepository: Bool,
        branchName: String? = nil,
        ahead: Int = 0,
        behind: Int = 0,
        stagedCount: Int = 0,
        unstagedCount: Int = 0,
        untrackedCount: Int = 0,
        files: [SDKFileChangeSummary] = []
    ) {
        self.isRepository = isRepository
        self.branchName = branchName
        self.ahead = ahead
        self.behind = behind
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.untrackedCount = untrackedCount
        self.files = files
    }
}

// MARK: - SDKDiffOptions
//
// Options for `sourceControl.getDiff()` (spec §11.2). Decoding is tolerant:
// absent keys fall back to the documented defaults, keeping the contract
// forward-compatible.

public struct SDKDiffOptions: Codable, Sendable {
    /// Maximum total diff bytes the host will return before truncating.
    /// Default 256 KiB (262144). Values < 1 are clamped to 1.
    public let maxBytes: Int
    /// Whether untracked files are included in the diff output.
    public let includeUntracked: Bool
    /// Optional repository-relative path filter; nil means the whole repo.
    /// Absolute paths are rejected by the host with INVALID_ARGUMENT.
    public let paths: [String]?

    private enum CodingKeys: String, CodingKey {
        case maxBytes, includeUntracked, paths
    }

    public init(maxBytes: Int = 262_144, includeUntracked: Bool = true, paths: [String]? = nil) {
        self.maxBytes = max(1, maxBytes)
        self.includeUntracked = includeUntracked
        self.paths = paths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.maxBytes = max(1, try container.decodeIfPresent(Int.self, forKey: .maxBytes) ?? 262_144)
        self.includeUntracked = try container.decodeIfPresent(Bool.self, forKey: .includeUntracked) ?? true
        self.paths = try container.decodeIfPresent([String].self, forKey: .paths)
    }
}

// MARK: - SDKFileDiff
//
// Bounded unified diff for a single file. `hunks` carries the raw unified
// diff text split per hunk so the TypeScript side can render incrementally.
// Binary files are never inlined: they appear with empty `hunks` and
// `truncated = true`.

public struct SDKFileDiff: Codable, Sendable {
    /// Repository-relative path. Never absolute (privacy).
    public let path: String
    /// Unified diff hunks (raw text, `@@ … @@` headers included).
    public let hunks: [String]
    /// True when this file's diff was cut short by the byte limit.
    public let truncated: Bool

    public init(path: String, hunks: [String], truncated: Bool = false) {
        self.path = path
        self.hunks = hunks
        self.truncated = truncated
    }
}

// MARK: - SDKRepositoryDiff
//
// Result of `sourceControl.getDiff()` (spec §11.2). The diff is always
// bounded: `truncated` + `totalBytes`/`byteLimit` tell the extension
// exactly how much was withheld, so truncation is explicit rather than
// silent.

public struct SDKRepositoryDiff: Codable, Sendable {
    /// Per-file diffs for files within the byte budget.
    public let files: [SDKFileDiff]
    /// True when output was cut short by the byte limit.
    public let truncated: Bool
    /// The full, untruncated byte size of the diff. May exceed `byteLimit`.
    public let totalBytes: Int
    /// The byte limit that was applied (echoes the effective `maxBytes`).
    public let byteLimit: Int

    public init(files: [SDKFileDiff], truncated: Bool, totalBytes: Int, byteLimit: Int) {
        self.files = files
        self.truncated = truncated
        self.totalBytes = totalBytes
        self.byteLimit = byteLimit
    }
}
