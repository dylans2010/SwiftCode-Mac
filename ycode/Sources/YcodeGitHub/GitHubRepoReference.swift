import Foundation

/// Parses the two ways a repository is named: `owner/repo` and a remote
/// URL. Never a network call — pure string parsing.
public enum GitHubRepoReference: Sendable {
    /// Parses `owner/repo`: surrounding whitespace is trimmed, a
    /// trailing `.git` is stripped, and anything with more or fewer
    /// than two non-empty segments is rejected.
    public static func parse(_ string: String) -> (owner: String, repo: String)? {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".git") {
            value = String(value.dropLast(4))
        }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !parts[0].contains(where: \.isWhitespace),
              !parts[1].contains(where: \.isWhitespace) else {
            return nil
        }
        return (parts[0], parts[1])
    }

    /// Parses a remote URL for a github.com repository:
    /// `https://github.com/owner/repo(.git)`,
    /// `git@github.com:owner/repo(.git)`, and
    /// `ssh://git@github.com/owner/repo(.git)`. Returns nil for any
    /// other host.
    public static func parseRemoteURL(_ string: String) -> (owner: String, repo: String)? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // SCP-like syntax: git@github.com:owner/repo(.git)
        if value.hasPrefix("git@github.com:") {
            return parse(String(value.dropFirst("git@github.com:".count)))
        }
        // URL syntax: https://github.com/owner/repo(.git),
        // ssh://git@github.com/owner/repo(.git)
        guard let url = URL(string: value),
              let host = url.host?.lowercased(), host == "github.com",
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "ssh" else {
            return nil
        }
        var path = url.path
        while path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }
        return parse(path)
    }
}
