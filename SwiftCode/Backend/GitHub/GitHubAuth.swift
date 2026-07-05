import Foundation

final class GitHubAuth {
    static let shared = GitHubAuth()
    private init() {}


    var token: String? {
        KeychainService.shared.get(forKey: KeychainService.githubToken)
    }

    var isAuthenticated: Bool {
        guard let t = token else { return false }
        return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainService.shared.set(trimmed, forKey: KeychainService.githubToken)
    }

    func clearToken() {
        KeychainService.shared.delete(forKey: KeychainService.githubToken)
    }

    func validateToken() async throws -> GitHubUser {
        guard isAuthenticated else { throw GitHubAuthError.missingToken }
        return try await GitHubAPIBackend.shared.getAuthenticatedUser()
    }

    func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

// MARK: - Errors

enum GitHubAuthError: LocalizedError {
    case missingToken
    case invalidToken

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No GitHub token found. Please add your personal access token in Settings."
        case .invalidToken:
            return "The GitHub token is invalid or has expired. Please update it to proceed."
        }
    }
}
