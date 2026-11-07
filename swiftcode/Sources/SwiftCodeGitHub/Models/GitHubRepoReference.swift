import Foundation

public enum GitHubRepoReference: Sendable {
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

    public static func parseRemoteURL(_ string: String) -> (owner: String, repo: String)? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@github.com:") {
            return parse(String(value.dropFirst("git@github.com:".count)))
        }
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
