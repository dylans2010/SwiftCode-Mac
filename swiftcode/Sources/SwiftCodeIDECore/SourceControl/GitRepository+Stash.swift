import Foundation

extension GitRepository {
    public func stashPatch(_ ref: String) throws -> String {
        guard ref.hasPrefix("stash@{") else { throw GitError(description: "\(ref) is not a stash") }
        return try git(["stash", "show", "-p", "--binary", ref])
    }

    public func exportStash(_ ref: String, to url: URL) throws {
        try stashPatch(ref).write(to: url, atomically: true, encoding: .utf8)
    }
}
