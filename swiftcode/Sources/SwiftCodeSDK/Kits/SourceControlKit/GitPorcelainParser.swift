// Ported from SwiftCode-Legacy `SwiftCode/Backend/Git/GitPorcelainParser.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Parses `git status --porcelain=v2 --branch` into a `GitStatusSnapshot`:
// branch name, ahead/behind counts, and one `GitFileStatus` per entry
// (`1 ` changed, `2 ` renamed, `? ` untracked). This is the v2 counterpart
// of the v1 parsing in `GitRepository.status()` (SwiftCodeIDECore) and
// `SDKSourceControlAdapter.parseStatus` (which reads the v1 `##` header):
// neither of those produces a `GitStatusSnapshot`, and neither reads the
// v2 `# branch.ab` / `1 ` / `2 ` lines.
//
// Adaptations for the destination:
// - `GitFileStatus.path` is a `String` here (destination model), not the
//   Legacy `URL`: paths are absolute (repository root + the v2 relative
//   path), exactly as Legacy produced them via
//   `repositoryURL.appendingPathComponent`.
// - Legacy's `GitFileStatus.Status.conflicted` (v2 `U`) had no counterpart
//   in the destination `StatusType`; `GitModels.swift` gains a
//   `.conflicted` case alongside this file.
// - Porcelain v2 separates a rename's two paths with a tab, and paths
//   containing spaces break the space split — Legacy had the same
//   limitation and this port keeps it rather than inventing new
//   behaviour; the new path (field 9) is used for renames.

import Foundation

public actor GitPorcelainParser {
    public static let shared = GitPorcelainParser()

    public init() {}

    public func parseStatus(_ output: String, repositoryURL: URL) -> GitStatusSnapshot {
        var branchName = "unknown"
        var ahead = 0
        var behind = 0
        var files: [GitFileStatus] = []

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("# branch.head ") {
                branchName = String(line.dropFirst(14))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.components(separatedBy: " ")
                if parts.count >= 4 {
                    ahead = Int(parts[2].dropFirst()) ?? 0
                    behind = Int(parts[3].dropFirst()) ?? 0
                }
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                // Changed / renamed. Field 2 is the XY status, field 9
                // the path (the new path for a rename).
                let parts = line.components(separatedBy: " ")
                if parts.count >= 9 {
                    let statusStr = String(parts[1])
                    let path = repositoryURL.appendingPathComponent(parts[8]).path
                    // SAFETY: statusStr is guaranteed to be non-empty in porcelain v2 output.
                    files.append(GitFileStatus(path: path, status: parseStatusChar(statusStr.first!), isStaged: statusStr.first != "."))
                }
            } else if line.hasPrefix("? ") {
                // Untracked
                let path = repositoryURL.appendingPathComponent(String(line.dropFirst(2))).path
                files.append(GitFileStatus(path: path, status: .untracked, isStaged: false))
            }
        }

        return GitStatusSnapshot(branchName: branchName, ahead: ahead, behind: behind, files: files)
    }

    private func parseStatusChar(_ char: Character) -> GitFileStatus.StatusType {
        switch char {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "U": return .conflicted
        default: return .modified
        }
    }
}
