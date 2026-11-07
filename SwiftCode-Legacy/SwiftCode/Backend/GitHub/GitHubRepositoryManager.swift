import Foundation

final class GitHubRepositoryManager: @unchecked Sendable {
    static let shared = GitHubRepositoryManager()
    private init() {}

    func fetchRepository(owner: String, repo: String) async throws -> GitHubRepoDetail {
        try await GitHubAPIBackend.shared.getRepository(owner: owner, repo: repo)
    }

    func fetchRepository(from urlString: String) async throws -> GitHubRepoDetail {
        let (owner, repo) = try parseRepoURL(urlString)
        return try await fetchRepository(owner: owner, repo: repo)
    }

    func listBranches(owner: String, repo: String) async throws -> [GitHubBranch] {
        try await GitHubAPIBackend.shared.listBranches(owner: owner, repo: repo)
    }

    func listCommits(owner: String, repo: String, branch: String = "main", count: Int = 20) async throws -> [GitHubCommit] {
        try await GitHubAPIBackend.shared.listCommits(owner: owner, repo: repo, branch: branch, perPage: count)
    }

    func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepo {
        try await GitHubAPIBackend.shared.createRepository(
            name: name,
            description: description,
            isPrivate: isPrivate
        )
    }

    func pushProject(_ project: Project, owner: String, repo: String, commitMessage: String) async throws {
        let allFiles = collectFiles(from: project.files)
        let projectDir = await project.directoryURL

        for fileNode in allFiles {
            let fileURL = projectDir.appendingPathComponent(fileNode.path)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let existingSHA = try? await GitHubAPIBackend.shared.getFileSHA(
                owner: owner,
                repo: repo,
                path: fileNode.path
            )
            try await GitHubAPIBackend.shared.pushFile(
                owner: owner,
                repo: repo,
                path: fileNode.path,
                content: content,
                message: commitMessage,
                sha: existingSHA
            )
        }
    }

    func pullFile(owner: String, repo: String, path: String, into project: Project) async throws {
        let content = try await GitHubAPIBackend.shared.getFileContent(owner: owner, repo: repo, path: path)
        let projectDir = await project.directoryURL
        let fileURL = projectDir.appendingPathComponent(path)
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func getRepositoryTree(owner: String, repo: String, branch: String = "main") async throws -> [GitHubTreeEntry] {
        try await GitHubAPIBackend.shared.getRepoTree(owner: owner, repo: repo, branch: branch)
    }

    private func collectFiles(from nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { node -> [FileNode] in
            node.isDirectory ? collectFiles(from: node.children) : [node]
        }
    }

    func parseRepoURL(_ urlString: String) throws -> (owner: String, repo: String) {
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

enum GitHubRepositoryError: LocalizedError {
    case invalidURL(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid GitHub repository URL: \(url)"
        case .notFound:
            return "Repository not found."
        }
    }
}
