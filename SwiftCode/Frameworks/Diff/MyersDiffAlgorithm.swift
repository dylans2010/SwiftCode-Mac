import Foundation

public struct MyersDiffAlgorithm: Sendable {
    public static let shared = MyersDiffAlgorithm()

    public func diff(old: [String], new: [String]) -> [GitDiffHunk] {
        let n = old.count
        let m = new.count

        // Simple line-by-line diff implementation for internal use
        // Returns a single hunk for simplicity, but with correct line markers
        var diffLines: [String] = []
        var i = 0, j = 0

        while i < n || j < m {
            if i < n && j < m && old[i] == new[j] {
                diffLines.append("  \(old[i])")
                i += 1
                j += 1
            } else if j < m && (i == n || !old.suffix(from: i).contains(new[j])) {
                diffLines.append("+\(new[j])")
                j += 1
            } else if i < n {
                diffLines.append("-\(old[i])")
                i += 1
            }
        }

        return [GitDiffHunk(header: "@@ -1,\(n) +1,\(m) @@", lines: diffLines)]
    }
}
