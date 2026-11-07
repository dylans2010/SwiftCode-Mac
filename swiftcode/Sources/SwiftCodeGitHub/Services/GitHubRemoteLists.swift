import Foundation

public struct GitHubNotification: Sendable, Equatable, Decodable, Identifiable {
    public var id: String
    public var unread: Bool
    public var reason: String
    public var subjectTitle: String
    public var subjectType: String
    public var subjectUrl: String?
    public var repositoryFullName: String
    public var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, unread, reason, subject, repository, updatedAt
    }

    private enum SubjectKeys: String, CodingKey {
        case title, type, url
    }

    private enum RepositoryKeys: String, CodingKey {
        case fullName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        unread = try container.decodeIfPresent(Bool.self, forKey: .unread) ?? false
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        let subject = try container.nestedContainer(keyedBy: SubjectKeys.self, forKey: .subject)
        subjectTitle = try subject.decode(String.self, forKey: .title)
        subjectType = try subject.decode(String.self, forKey: .type)
        subjectUrl = try subject.decodeIfPresent(String.self, forKey: .url)
        let repository = try container.nestedContainer(keyedBy: RepositoryKeys.self, forKey: .repository)
        repositoryFullName = try repository.decode(String.self, forKey: .fullName)
    }
}

public struct GitHubOrganization: Sendable, Equatable, Decodable, Identifiable {
    public var id: Int
    public var login: String
    public var description: String?
    public var avatarUrl: String?
}

public struct GitHubRepositoryEvent: Sendable, Equatable, Decodable, Identifiable {
    public var id: String
    public var type: String
    public var actorLogin: String?
    public var repoFullName: String
    public var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, type, actor, repo, createdAt
    }

    private enum ActorKeys: String, CodingKey {
        case login
    }

    private enum RepoKeys: String, CodingKey {
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        if let actor = try? container.nestedContainer(keyedBy: ActorKeys.self, forKey: .actor) {
            actorLogin = try actor.decodeIfPresent(String.self, forKey: .login)
        } else {
            actorLogin = nil
        }
        let repo = try container.nestedContainer(keyedBy: RepoKeys.self, forKey: .repo)
        repoFullName = try repo.decode(String.self, forKey: .name)
    }
}

public struct GitHubRemoteListsClient: Sendable {
    private let transport: GitHubRESTTransport

    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { nil }) {
        self.transport = GitHubRESTTransport(session: session, tokenProvider: tokenProvider)
    }

    public func listNotifications(all: Bool = false, perPage: Int = 30, page: Int = 1) async throws -> [GitHubNotification] {
        try requireToken()
        return try await transport.perform(transport.request(
            path: "notifications",
            query: [URLQueryItem(name: "all", value: all ? "true" : "false"),
                    URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))"),
                    URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    public func markNotificationRead(threadId: String) async throws {
        try requireToken()
        let id = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw GitHubError.unprocessable(message: "A notification thread ID is required")
        }
        try await transport.performVoid(transport.request(
            path: "notifications/threads/\(transport.encode(id))", method: "PATCH"))
    }

    public func listOrganizations(perPage: Int = 30) async throws -> [GitHubOrganization] {
        try requireToken()
        return try await transport.perform(transport.request(
            path: "user/orgs",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))")]))
    }

    public func listUserRepositories(perPage: Int = 30, page: Int = 1) async throws -> [GitHubRepository] {
        try requireToken()
        return try await transport.perform(transport.request(
            path: "user/repos",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))"),
                    URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    public func searchRepositories(query: String, perPage: Int = 30, page: Int = 1) async throws -> GitHubSearchResult<GitHubRepository> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitHubError.unprocessable(message: "A search query is required")
        }
        return try await transport.perform(transport.request(
            path: "search/repositories",
            query: [URLQueryItem(name: "q", value: trimmed),
                    URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))"),
                    URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    public func listRepositoryEvents(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubRepositoryEvent] {
        try validateRepo(owner: owner, repo: repo)
        return try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/events",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))")]))
    }

    public func createRepository(name: String, description: String?, isPrivate: Bool, autoInit: Bool = false) async throws -> GitHubRepository {
        try requireToken()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            throw GitHubError.unprocessable(message: "A repository name is required")
        }
        let body = try transport.jsonBody(RepositoryCreateBody(
            name: trimmed, description: description, isPrivate: isPrivate, autoInit: autoInit))
        return try await transport.perform(transport.request(path: "user/repos", method: "POST", body: body))
    }

    private func requireToken() throws {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
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

private struct RepositoryCreateBody: Encodable {
    var name: String
    var description: String?
    var isPrivate: Bool
    var autoInit: Bool

    private enum CodingKeys: String, CodingKey {
        case name, description
        case isPrivate = "private"
        case autoInit = "auto_init"
    }
}
