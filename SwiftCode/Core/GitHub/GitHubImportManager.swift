import Foundation

final class GitHubImportManager {
    static let shared = GitHubImportManager()
    private init() {}

    // MARK: - Import from URL
    func importRepository(from urlString: String, branch: String = "main") async throws -> Project {
        try await GitHubImporter.shared.importRepository(from: urlString, branch: branch)
    }

    func importRepository(owner: String, repo: String, branch: String = "main") async throws -> Project {
        try await GitHubImporter.shared.importRepository(owner: owner, repo: repo, branch: branch)
    }
}
