import Foundation

public struct GitHubIssueComment: Sendable, Equatable, Decodable, Identifiable {
    public var id: Int
    public var body: String
    public var userLogin: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var htmlUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id, body, createdAt, updatedAt, htmlUrl, user
    }

    private enum UserKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        htmlUrl = try container.decodeIfPresent(String.self, forKey: .htmlUrl)
        let user = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        userLogin = try user.decode(String.self, forKey: .login)
    }
}

public struct GitHubIssueCommentClient: Sendable {
    private let transport: GitHubRESTTransport

    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { nil }) {
        self.transport = GitHubRESTTransport(session: session, tokenProvider: tokenProvider)
    }

    public func listIssueComments(owner: String, repo: String, number: Int, perPage: Int = 30) async throws -> [GitHubIssueComment] {
        try validateRepo(owner: owner, repo: repo)
        return try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/issues/\(number)/comments",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))")]))
    }

    public func createIssueComment(owner: String, repo: String, number: Int, body: String) async throws -> GitHubIssueComment {
        try validateRepo(owner: owner, repo: repo)
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitHubError.unprocessable(message: "A comment body is required")
        }
        let payload = try transport.jsonBody(CommentBody(body: trimmed))
        return try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/issues/\(number)/comments",
            method: "POST", body: payload))
    }

    public func updateIssueComment(owner: String, repo: String, commentId: Int, body: String) async throws -> GitHubIssueComment {
        try validateRepo(owner: owner, repo: repo)
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitHubError.unprocessable(message: "A comment body is required")
        }
        let payload = try transport.jsonBody(CommentBody(body: trimmed))
        return try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/issues/comments/\(commentId)",
            method: "PATCH", body: payload))
    }

    public func deleteIssueComment(owner: String, repo: String, commentId: Int) async throws {
        try validateRepo(owner: owner, repo: repo)
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        try await transport.performVoid(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/issues/comments/\(commentId)",
            method: "DELETE"))
    }

    private func validateRepo(owner: String, repo: String) throws {
        let owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repo.isEmpty,
              !owner.contains("/"), !repo.contains("/") else {
            throw GitHubError.invalidRepo("\(owner)/\(repo)")
        }
    }
}

private struct CommentBody: Encodable {
    var body: String
}
