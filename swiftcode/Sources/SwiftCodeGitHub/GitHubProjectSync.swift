import Foundation

/// Pushes and pulls whole local directories to and from a GitHub
/// repository through the Contents API.
///
/// This is the portable remainder of Legacy's `GitHubRepositoryManager`
/// (`pushProject` / `pullFile`) and `GitCommands` (`push` / `pull`):
/// Legacy drove them off its `Project` model (`FileNode` tree +
/// `ProjectSessionStore` refresh), which does not exist in SwiftCode, so this
/// works from a plain directory URL instead — enumerate the directory,
/// read each readable text file, and push it with the client's Contents
/// API; pull a file with the client's `getFileText`.
///
/// It builds on the client methods gap-closure landed in
/// `GitHubClient` (`pushFile(owner:repo:path:content:message:sha:branch:)`,
/// `getFileSHA`, `getFileText`): this file does not reimplement the HTTP
/// layer. The repository itself is created by `GitHubClient.createRepository`
/// (also gap-closure); this file assumes the repo already exists.
///
/// Binary and unreadable files are skipped on push (Legacy's `pushProject`
/// had the same behaviour: it only pushed files it could read as text).
/// The `.git` directory and hidden files are skipped.
public struct GitHubProjectSync: Sendable {
    private let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    /// Pushes every readable text file under `directory` to `owner/repo`
    /// (recursively, paths relative to `directory`), returning the number
    /// of files pushed. Existing files are updated in place (their SHA is
    /// fetched first, so the push does not conflict).
    @discardableResult
    public func pushDirectory(_ directory: URL, owner: String, repo: String, commitMessage: String, branch: String? = nil) async throws -> Int {
        let files = collectTextFiles(in: directory)
        var pushed = 0
        for file in files {
            let relativePath = file.path.replacingOccurrences(of: directory.path + "/", with: "")
            let content = try String(contentsOf: file, encoding: .utf8)
            let sha = try? await client.getFileSHA(owner: owner, repo: repo, path: relativePath)
            _ = try await client.pushFile(owner: owner, repo: repo, path: relativePath, content: content, message: commitMessage, sha: sha, branch: branch)
            pushed += 1
        }
        return pushed
    }

    /// Pulls one file from `owner/repo` and writes it into `directory`
    /// (creating intermediate directories). Returns the written URL.
    @discardableResult
    public func pullFile(owner: String, repo: String, path: String, into directory: URL, ref: String? = nil) async throws -> URL {
        let text = try await client.getFileText(owner: owner, repo: repo, path: path, ref: ref)
        let destination = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    /// Pulls a whole project from `owner/repo` into `directory` (Legacy
    /// `GitCommands.pull`): fetches the repo tree for `branch`, then
    /// pulls every blob into the directory (creating intermediate
    /// directories), returning the number of files pulled. A failed
    /// tree fetch or file pull aborts with the underlying error wrapped
    /// as `GitCommandsError.pullFailed`, as Legacy's `pullFailed` did.
    /// The Legacy `ProjectSessionStore.refreshFileTree` step has no
    /// destination equivalent (no `Project` model); callers refresh
    /// their own file tree after the pull returns.
    @discardableResult
    public func pullDirectory(owner: String, repo: String, branch: String = "main", into directory: URL) async throws -> Int {
        let tree: [GitHubTreeEntry]
        do {
            tree = try await client.getRepoTree(owner: owner, repo: repo, ref: branch)
        } catch {
            throw GitCommandsError.pullFailed(error.localizedDescription)
        }
        let files = tree.filter { $0.type == "blob" }
        var pulled = 0
        for entry in files {
            do {
                _ = try await pullFile(owner: owner, repo: repo, path: entry.path, into: directory, ref: branch)
                pulled += 1
            } catch {
                throw GitCommandsError.pullFailed(error.localizedDescription)
            }
        }
        return pulled
    }

    /// The text files under `directory` that `pushDirectory` would push
    /// (relative paths). Exposed for callers that want to preview a push.
    public func textFiles(in directory: URL) -> [String] {
        collectTextFiles(in: directory).map { $0.path.replacingOccurrences(of: directory.path + "/", with: "") }
    }

    private func collectTextFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains(".git") { continue }
            guard fileURL.pathExtension.lowercased() != "png",
                  fileURL.pathExtension.lowercased() != "jpg",
                  fileURL.pathExtension.lowercased() != "jpeg",
                  fileURL.pathExtension.lowercased() != "gif",
                  fileURL.pathExtension.lowercased() != "icns",
                  fileURL.pathExtension.lowercased() != "zip" else { continue }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard (try? String(contentsOf: fileURL, encoding: .utf8)) != nil else { continue }
            files.append(fileURL)
        }
        return files.sorted(by: { $0.path < $1.path })
    }
}
