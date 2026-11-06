// Ported from SwiftCode-Legacy `SwiftCode/Backend/Git/GitService.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Legacy `GitService` as a whole is superseded: status/stage/unstage/
// discard/commit/clone/log/branches/checkout/deleteBranch/push/rollback
// live in `GitRepository` / `GitHistory` and the `version_control_operator`
// MCP tools. These are the three pieces that had no destination
// equivalent:
//
// - `isGitInstalled()` — the git-executable probe (Legacy resolved the
//   `git_executable_path` preference, then the usual Homebrew/system
//   paths; the same resolution already lives in the destination's
//   `WorktreeManager.gitExecutableURL`, and is mirrored here).
// - `forcePush()` — COVERED, no code staged: `GitRepository.push(remote:
//   branch:setUpstream:force:)` (`GitRepository+Branches.swift`) already
//   pushes with `--force-with-lease`, the safer form of Legacy's
//   `--force`. Callers use `push(force: true)`.
// - `parseDiff()` — structured hunk parsing. Legacy returned
//   `[GitDiffHunk]` (header string + lines); the destination's local
//   equivalent is `DiffHunk` (parsed `@@` ranges + lines), so the
//   parser targets `DiffHunk` and also gains a `diffHunks()` that runs
//   `git diff` itself, matching Legacy's `getDiff()`.

import Foundation

extension GitRepository {

    // MARK: - Git availability (Legacy `GitService.isGitInstalled`)

    /// Whether a usable git executable exists: the `git_executable_path`
    /// preference first, then the usual Homebrew/system locations.
    public static func isGitInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: resolvedGitPath())
    }

    /// The git executable `isGitInstalled()` probes, mirroring
    /// `WorktreeManager`'s resolution.
    public static func resolvedGitPath() -> String {
        if let customPath = UserDefaults.standard.string(forKey: "git_executable_path"), !customPath.isEmpty {
            return customPath
        }
        for path in ["/usr/local/bin/git", "/opt/homebrew/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git", "/usr/bin/git"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/usr/bin/git"
    }

    // MARK: - Structured diffs (Legacy `GitService.getDiff` / `parseDiff`)

    /// The working-tree diff as structured hunks (`git diff`, parsed).
    /// Throws when git itself fails, as `diff(of:)`'s raw-text twin does.
    public func diffHunks() throws -> [DiffHunk] {
        let output = try git(["diff", "--no-color"])
        return Self.parseDiff(output)
    }

    /// Parses `git diff` output into hunks. Each `@@ -a[,b] +c[,d] @@`
    /// header starts a hunk; lines before the first header (the
    /// `diff --git` / `index` / `---` / `+++` file headers) are skipped,
    /// as in Legacy. A missing `,count` means a count of 1.
    public static func parseDiff(_ output: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentHeader: (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)?
        var currentLines: [String] = []

        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("@@ ") {
                if let header = currentHeader {
                    hunks.append(DiffHunk(oldStart: header.oldStart, oldCount: header.oldCount, newStart: header.newStart, newCount: header.newCount, lines: currentLines))
                }
                currentHeader = parseHunkHeader(line)
                currentLines = []
            } else if currentHeader != nil {
                currentLines.append(line)
            }
        }
        if let header = currentHeader {
            hunks.append(DiffHunk(oldStart: header.oldStart, oldCount: header.oldCount, newStart: header.newStart, newCount: header.newCount, lines: currentLines))
        }
        return hunks
    }

    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        // "@@ -12,3 +12,4 @@ optional section heading"
        let pattern = #"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 5,
              let oldStart = intGroup(match, 1, in: line),
              let newStart = intGroup(match, 3, in: line) else { return nil }
        let oldCount = intGroup(match, 2, in: line) ?? 1
        let newCount = intGroup(match, 4, in: line) ?? 1
        return (oldStart, oldCount, newStart, newCount)
    }

    private static func intGroup(_ match: NSTextCheckingResult, _ index: Int, in line: String) -> Int? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else { return nil }
        return Int(line[swiftRange])
    }
}
