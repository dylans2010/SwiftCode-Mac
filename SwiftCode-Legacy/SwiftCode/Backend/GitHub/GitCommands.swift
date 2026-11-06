import Foundation


final class GitCommands: @unchecked Sendable {
    static let shared = GitCommands()
    private init() {}

    func push(project: Project, commitMessage: String) async throws {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            throw GitCommandsError.missingRemote
        }
        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)
        try await GitHubRepositoryManager.shared.pushProject(
            project,
            owner: owner,
            repo: repo,
            commitMessage: commitMessage
        )
    }


    func pushFile(path: String, content: String, commitMessage: String, project: Project) async throws {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            throw GitCommandsError.missingRemote
        }
        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)
        let existingSHA = try? await GitHubAPIBackend.shared.getFileSHA(owner: owner, repo: repo, path: path)
        try await GitHubAPIBackend.shared.pushFile(
            owner: owner,
            repo: repo,
            path: path,
            content: content,
            message: commitMessage,
            sha: existingSHA
        )
    }


    func pull(project: Project, branch: String = "main") async throws {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            throw GitCommandsError.missingRemote
        }
        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)
        let tree = try await GitHubAPIBackend.shared.getRepoTree(owner: owner, repo: repo, branch: branch)
        let files = tree.filter { $0.type == "blob" }

        for entry in files {
            try await GitHubRepositoryManager.shared.pullFile(
                owner: owner,
                repo: repo,
                path: entry.path,
                into: project
            )
        }

        await MainActor.run {
            ProjectSessionStore.shared.refreshFileTree(for: project)
        }
    }

    func listBranches(for project: Project) async throws -> [GitHubBranch] {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            throw GitCommandsError.missingRemote
        }
        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)
        return try await GitHubAPIBackend.shared.listBranches(owner: owner, repo: repo)
    }


    func recentCommits(for project: Project, branch: String = "main", count: Int = 20) async throws -> [GitHubCommit] {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            throw GitCommandsError.missingRemote
        }
        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)
        return try await GitHubAPIBackend.shared.listCommits(
            owner: owner,
            repo: repo,
            branch: branch,
            perPage: count
        )
    }
}


enum GitCommandsError: LocalizedError {
    case missingRemote
    case pushFailed(String)
    case pullFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRemote:
            return "No GitHub repository is linked to this project. Please set a repository URL in the GitHub settings."
        case .pushFailed(let reason):
            return "Push Failed: \(reason)"
        case .pullFailed(let reason):
            return "Pull Failed: \(reason)"
        }
    }
}
