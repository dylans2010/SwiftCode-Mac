import Foundation

public final class GitHubRepositoryManager: @unchecked Sendable {
    public static let shared = GitHubRepositoryManager()
    private init() {}

    public func fetchRepository(owner: String, repo: String) async throws -> GitHubRepository {
        try await GitHubService.shared.getRepository(owner: owner, repo: repo)
    }

    public func fetchRepository(from urlString: String) async throws -> GitHubRepository {
        let (owner, repo) = try parseRepoURL(urlString)
        return try await fetchRepository(owner: owner, repo: repo)
    }

    public func listBranches(owner: String, repo: String) async throws -> [GitHubBranch] {
        try await GitHubService.shared.listBranches(owner: owner, repo: repo)
    }

    public func listCommits(owner: String, repo: String, branch: String = "main", count: Int = 20) async throws -> [GitHubCommit] {
        try await GitHubService.shared.listCommits(owner: owner, repo: repo, branch: branch, perPage: count)
    }

    public func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepository {
        try await GitHubService.shared.createRepository(
            name: name,
            description: description,
            isPrivate: isPrivate
        )
    }

    public func pushProject(_ files: [(path: String, data: Data)], owner: String, repo: String, branch: String = "main", commitMessage: String) async throws {
        try await GitHubService.shared.pushProject(
            owner: owner,
            repo: repo,
            branch: branch,
            commitMessage: commitMessage,
            files: files
        )
    }

    @discardableResult
    public func pullFile(owner: String, repo: String, path: String, into directory: URL, ref: String? = nil) async throws -> URL {
        let content = try await GitHubService.shared.getFileText(owner: owner, repo: repo, path: path, ref: ref)
        let fileURL = directory.appendingPathComponent(path)
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    public func getRepositoryTree(owner: String, repo: String, branch: String = "main") async throws -> [GitHubTreeEntry] {
        try await GitHubService.shared.getRepoTree(owner: owner, repo: repo, branch: branch)
    }

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
