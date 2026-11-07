import Foundation

public final class GitHubImportManager: Sendable {
    public static let shared = GitHubImportManager()
    private init() {}

    public func importRepository(from urlString: String, branch: String = "main") async throws -> SCProject {
        try await GitHubImporter.shared.importRepository(from: urlString, branch: branch)
    }

    public func importRepository(owner: String, repo: String, branch: String = "main") async throws -> SCProject {
        try await GitHubImporter.shared.importRepository(owner: owner, repo: repo, branch: branch)
    }
}
