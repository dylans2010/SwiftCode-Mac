import Foundation

public struct GitPorcelainParser: Sendable {
    public static let shared = GitPorcelainParser()

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
                // Modified/Staged etc
                let parts = line.components(separatedBy: " ")
                if parts.count >= 9 {
                    let statusStr = String(parts[1])
                    let path = repositoryURL.appendingPathComponent(parts[8])
                    files.append(GitFileStatus(path: path, status: parseStatusChar(statusStr.first!), isStaged: statusStr.first != "."))
                }
            } else if line.hasPrefix("? ") {
                // Untracked
                let path = repositoryURL.appendingPathComponent(String(line.dropFirst(2)))
                files.append(GitFileStatus(path: path, status: .untracked, isStaged: false))
            }
        }

        return GitStatusSnapshot(branchName: branchName, ahead: ahead, behind: behind, files: files)
    }

    private func parseStatusChar(_ char: Character) -> GitFileStatus.Status {
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
