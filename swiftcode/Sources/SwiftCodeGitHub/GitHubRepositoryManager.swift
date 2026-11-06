// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/GitHub/GitHubRepositoryManager.swift (Legacy main ab03f681)
//
// Destination: SwiftCodeGitHub/GitHubRepositoryManager.swift.
//
// Adaptations (behaviour preserved unless noted):
// * Legacy drove every method through `GitHubAPIBackend.shared`, which was
//   never ported. The production equivalent is `GitHubService.shared`
//   (same token, same REST surface); the read methods it did not expose
//   (`getRepository`, `listBranches`, `createRepository`, `getRepoTree`,
//   `getFileText`) are thin passthroughs added to `GitHubService` in this
//   same wave — this manager does not construct its own `GitHubClient`,
//   which would have no token.
// * `fetchRepository` returns `GitHubRepository`, the production
//   equivalent of Legacy's `GitHubRepoDetail` (same fields; `id` is the
//   `owner/name` full name instead of the numeric id). `createRepository`
//   likewise returns `GitHubRepository` instead of Legacy's five-field
//   `GitHubRepo` (a strict subset of the same fields).
// * `pushProject` takes `files: [(path: String, data: Data)]` and
//   delegates to `GitHubService.shared.pushProject` (Git Data API:
//   blobs → tree → commit → ref update). Legacy's version took a
//   `Project` and pushed file-by-file through the Contents API; that
//   shape cannot live in this module (`SwiftCodeGitHub` has no
//   `SwiftCodeIDECore` dependency), and the Contents-API per-file push
//   already exists as `GitHubProjectSync`. Callers that own a `Project`
//   collect the files themselves (see `DeploymentTargets`).
// * `pullFile` takes `into directory: URL` and returns the written URL,
//   instead of Legacy's `into project: Project` (same module reason).
// * `listCommits` keeps Legacy's default `count: 20` (production
//   `GitHubService.listCommits` defaults to 10).
// * `parseRepoURL` is verbatim. It is the method the landed call sites
//   actually use (`DeploymentTargets`, `PrepareCompileWaitingView`).
// * `GitHubRepositoryError` is verbatim, made `public` with the manager.

import Foundation

/// Manages GitHub repository operations: cloning, listing, and metadata retrieval.
///
/// This manager maintains the relationship between local projects and their
/// remote GitHub repositories, and supports creating new repositories via the API.
public final class GitHubRepositoryManager: @unchecked Sendable {
    public static let shared = GitHubRepositoryManager()
    private init() {}

    // MARK: - Fetch Repository Info

    /// Fetch metadata for a repository by owner and repo name.
    public func fetchRepository(owner: String, repo: String) async throws -> GitHubRepository {
        try await GitHubService.shared.getRepository(owner: owner, repo: repo)
    }

    /// Fetch metadata for a repository from a full GitHub URL.
    public func fetchRepository(from urlString: String) async throws -> GitHubRepository {
        let (owner, repo) = try parseRepoURL(urlString)
        return try await fetchRepository(owner: owner, repo: repo)
    }

    // MARK: - List Branches

    public func listBranches(owner: String, repo: String) async throws -> [GitHubBranch] {
        try await GitHubService.shared.listBranches(owner: owner, repo: repo)
    }

    // MARK: - List Commits

    public func listCommits(owner: String, repo: String, branch: String = "main", count: Int = 20) async throws -> [GitHubCommit] {
        try await GitHubService.shared.listCommits(owner: owner, repo: repo, branch: branch, perPage: count)
    }

    // MARK: - Create Repository

    /// Create a new GitHub repository for the given project.
    public func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepository {
        try await GitHubService.shared.createRepository(
            name: name,
            description: description,
            isPrivate: isPrivate
        )
    }

    // MARK: - Push All Project Files

    /// Push all files to a GitHub repository through the Git Data API
    /// (blobs → tree → commit → ref update), as `GitHubService.pushProject`.
    /// Callers pass the collected `(path, data)` pairs — relative paths
    /// from the project root, file contents as data.
    public func pushProject(_ files: [(path: String, data: Data)], owner: String, repo: String, branch: String = "main", commitMessage: String) async throws {
        try await GitHubService.shared.pushProject(
            owner: owner,
            repo: repo,
            branch: branch,
            commitMessage: commitMessage,
            files: files
        )
    }

    // MARK: - Pull File from Remote

    /// Pull (download) a single file from a GitHub repository and save it
    /// under `directory` (creating intermediate directories). Returns the
    /// written file URL.
    @discardableResult
    public func pullFile(owner: String, repo: String, path: String, into directory: URL, ref: String? = nil) async throws -> URL {
        let content = try await GitHubService.shared.getFileText(owner: owner, repo: repo, path: path, ref: ref)
        let fileURL = directory.appendingPathComponent(path)
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Repository Tree

    /// Retrieve the full recursive file tree from a GitHub repository.
    public func getRepositoryTree(owner: String, repo: String, branch: String = "main") async throws -> [GitHubTreeEntry] {
        try await GitHubService.shared.getRepoTree(owner: owner, repo: repo, branch: branch)
    }

    // MARK: - Helpers

    public func parseRepoURL(_ urlString: String) throws -> (owner: String, repo: String) {
        let cleaned = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "http://github.com/", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let parts = cleaned.split(separator: "/", maxSplits: 2)
        guard parts.count >= 2 else {
            throw GitHubRepositoryError.invalidURL(urlString)
        }
        let owner = String(parts[0])
        let repo = String(parts[1]).replacingOccurrences(of: ".git", with: "")
        guard !owner.isEmpty, !repo.isEmpty else {
            throw GitHubRepositoryError.invalidURL(urlString)
        }
        return (owner, repo)
    }
}

// MARK: - Errors

public enum GitHubRepositoryError: LocalizedError {
    case invalidURL(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid GitHub repository URL: \(url)"
        case .notFound:
            return "Repository not found."
        }
    }
}
