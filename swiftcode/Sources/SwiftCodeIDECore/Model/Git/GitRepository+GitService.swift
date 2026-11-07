import Foundation

extension GitRepository {

    public static func isGitInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: resolvedGitPath())
    }

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

    public func diffHunks() throws -> [DiffHunk] {
        let output = try git(["diff", "--no-color"])
        return Self.parseDiff(output)
    }

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
