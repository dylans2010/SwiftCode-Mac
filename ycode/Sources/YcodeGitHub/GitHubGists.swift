import Foundation

/// A gist (`GET /gists`, `GET /gists/{id}`). `files` is the API's
/// filename-keyed dictionary; `sortedFiles` is the display order.
/// `owner` is nil for anonymous gists.
public struct GitHubGist: Sendable, Equatable, Decodable, Identifiable {
    public var id: String
    public var description: String?
    public var isPublic: Bool
    public var owner: GitHubUser?
    public var files: [String: GitHubGistFile]
    public var comments: Int
    public var createdAt: Date?
    public var updatedAt: Date?
    public var htmlUrl: String?
    /// The revisions from the `history` key of `GET /gists/{id}`.
    public var history: [GitHubGistRevision]

    public var sortedFiles: [GitHubGistFile] {
        files.values.sorted { $0.filename < $1.filename }
    }

    private enum CodingKeys: String, CodingKey {
        case id, description, owner, files, comments, createdAt, updatedAt, htmlUrl, history
        case isPublic = "public"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        owner = try container.decodeIfPresent(GitHubUser.self, forKey: .owner)
        comments = try container.decodeIfPresent(Int.self, forKey: .comments) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        htmlUrl = try container.decodeIfPresent(String.self, forKey: .htmlUrl)
        history = try container.decodeIfPresent([GitHubGistRevision].self, forKey: .history) ?? []
        // The API normally repeats the filename inside each value; when
        // it does not, the dictionary key is the filename.
        let rawFiles = try container.decodeIfPresent([String: GitHubGistFile].self, forKey: .files) ?? [:]
        var filled: [String: GitHubGistFile] = [:]
        for (key, var file) in rawFiles {
            if file.filename.isEmpty { file.filename = key }
            filled[key] = file
        }
        files = filled
    }
}

/// One file of a gist. `content` is present only on a single-gist
/// fetch (`GET /gists/{id}`); list responses omit it.
public struct GitHubGistFile: Sendable, Equatable, Decodable, Identifiable {
    public var id: String { filename }
    public var filename: String
    public var type: String?
    public var language: String?
    public var rawUrl: String?
    public var size: Int?
    public var content: String?
    public var truncated: Bool?

    private enum CodingKeys: String, CodingKey {
        case filename, type, language, rawUrl, size, content, truncated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        rawUrl = try container.decodeIfPresent(String.self, forKey: .rawUrl)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated)
    }
}

/// A comment on a gist (`GET /gists/{id}/comments`).
public struct GitHubGistComment: Sendable, Equatable, Decodable, Identifiable {
    public var id: Int
    public var body: String
    public var user: GitHubUser?
    public var createdAt: Date?
    public var updatedAt: Date?
}

/// One entry of a gist's `history` (`GET /gists/{id}`): the revision
/// `GET /gists/{id}/{sha}` returns. `changeStatus` is the
/// `change_status` object (`additions` / `deletions` / `total`).
public struct GitHubGistRevision: Sendable, Equatable, Decodable, Identifiable {
    public var id: String { version }
    public var version: String
    public var user: GitHubUser?
    public var committedAt: Date?
    public var changeStatus: GitHubGistChangeStatus?

    private enum CodingKeys: String, CodingKey {
        // Raw values are the post-conversion camelCase forms: the
        // decoder's `.convertFromSnakeCase` turns `change_status`
        // into `changeStatus` before matching.
        case version, user, committedAt, changeStatus
    }
}

/// The `change_status` object of a gist revision.
public struct GitHubGistChangeStatus: Sendable, Equatable, Decodable {
    public var additions: Int
    public var deletions: Int
    public var total: Int
}

/// The api.github.com gist client. There is no gist surface in
/// `GitHubClient` (Wave 10), so this is the port of Legacy's
/// `GitHubGistService` (`SwiftCode/Views/Gists/`): the same endpoints
/// the Legacy gist views drove — list, fetch, create, update, delete,
/// star, comments, revisions — over `GitHubRESTTransport`. The token
/// is optional: unauthenticated requests read public gists at
/// GitHub's lower rate limit. The token itself is never stored here.
public struct GitHubGistClient: Sendable {
    private let transport: GitHubRESTTransport

    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { nil }) {
        self.transport = GitHubRESTTransport(session: session, tokenProvider: tokenProvider)
    }

    /// `GET /gists`: the authenticated user's gists. Requires a token.
    public func listGists(perPage: Int = 30, page: Int = 1) async throws -> [GitHubGist] {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        return try await transport.perform(transport.request(
            path: "gists",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))"),
                    URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    /// `GET /gists/starred`: the authenticated user's starred gists.
    /// Requires a token.
    public func listStarredGists(perPage: Int = 30, page: Int = 1) async throws -> [GitHubGist] {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        return try await transport.perform(transport.request(
            path: "gists/starred",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))"),
                    URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    /// `GET /users/{username}/gists`: a user's public gists.
    public func listUserGists(username: String, perPage: Int = 30, page: Int = 1) async throws -> [GitHubGist] {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else {
            throw GitHubError.invalidRepo(name)
        }
        return try await transport.perform(transport.request(
            path: "users/\(transport.encode(name))/gists",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))"),
                    URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    /// `GET /gists/{id}`: one gist, with file contents and `history`.
    public func fetchGist(id: String) async throws -> GitHubGist {
        let gistId = try validatedId(id)
        return try await transport.perform(transport.request(path: "gists/\(transport.encode(gistId))"))
    }

    /// `POST /gists`. `files` maps filename to content.
    public func createGist(description: String?, isPublic: Bool, files: [String: String]) async throws -> GitHubGist {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        guard !files.isEmpty else {
            throw GitHubError.unprocessable(message: "A gist needs at least one file")
        }
        let body = try transport.jsonBody(GistCreateBody(
            description: description,
            isPublic: isPublic,
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.key, GistFileBody(content: $0.value)) })))
        return try await transport.perform(transport.request(path: "gists", method: "POST", body: body))
    }

    /// `PATCH /gists/{id}`. `files` maps filename to new content, or
    /// `nil` to delete that file. Only non-nil fields are sent.
    public func updateGist(id: String, description: String?, files: [String: String?]) async throws -> GitHubGist {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let gistId = try validatedId(id)
        let body = try transport.jsonBody(GistUpdateBody(
            description: description,
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.key, GistFileBody(content: $0.value)) })))
        return try await transport.perform(transport.request(path: "gists/\(transport.encode(gistId))", method: "PATCH", body: body))
    }

    /// `DELETE /gists/{id}`.
    public func deleteGist(id: String) async throws {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let gistId = try validatedId(id)
        try await transport.performVoid(transport.request(path: "gists/\(transport.encode(gistId))", method: "DELETE"))
    }

    /// `GET /gists/{id}/star`: 204 when starred, 404 when not.
    public func isStarred(id: String) async throws -> Bool {
        let gistId = try validatedId(id)
        do {
            try await transport.performVoid(transport.request(path: "gists/\(transport.encode(gistId))/star"))
            return true
        } catch GitHubError.notFound {
            return false
        }
    }

    /// `PUT /gists/{id}/star`.
    public func starGist(id: String) async throws {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let gistId = try validatedId(id)
        try await transport.performVoid(transport.request(path: "gists/\(transport.encode(gistId))/star", method: "PUT"))
    }

    /// `DELETE /gists/{id}/star`.
    public func unstarGist(id: String) async throws {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let gistId = try validatedId(id)
        try await transport.performVoid(transport.request(path: "gists/\(transport.encode(gistId))/star", method: "DELETE"))
    }

    /// `GET /gists/{id}/comments`.
    public func fetchComments(gistId: String) async throws -> [GitHubGistComment] {
        let id = try validatedId(gistId)
        return try await transport.perform(transport.request(path: "gists/\(transport.encode(id))/comments"))
    }

    /// `POST /gists/{id}/comments`.
    public func createComment(gistId: String, body: String) async throws -> GitHubGistComment {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let id = try validatedId(gistId)
        let payload = try transport.jsonBody(GistCommentBody(body: body))
        return try await transport.perform(transport.request(path: "gists/\(transport.encode(id))/comments", method: "POST", body: payload))
    }

    /// The `history` of `GET /gists/{id}`: the gist's revisions.
    public func fetchRevisions(gistId: String) async throws -> [GitHubGistRevision] {
        let gist = try await fetchGist(id: gistId)
        return gist.history
    }

    /// `GET /gists/{id}/{sha}`: the gist as it was at one revision.
    public func fetchGistAtRevision(id: String, sha: String) async throws -> GitHubGist {
        let gistId = try validatedId(id)
        let revision = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty else {
            throw GitHubError.unprocessable(message: "A revision SHA is required")
        }
        return try await transport.perform(transport.request(
            path: "gists/\(transport.encode(gistId))/\(transport.encode(revision))"))
    }

    private func validatedId(_ id: String) throws -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            throw GitHubError.unprocessable(message: "A gist ID is required")
        }
        return trimmed
    }
}

// MARK: - Private bodies

/// `POST /gists`. Nil fields are omitted.
private struct GistCreateBody: Encodable {
    var description: String?
    var isPublic: Bool
    var files: [String: GistFileBody]

    private enum CodingKeys: String, CodingKey {
        case description, files
        case isPublic = "public"
    }
}

/// `PATCH /gists/{id}`. Nil fields are omitted; a file with a nil
/// `content` is deleted.
private struct GistUpdateBody: Encodable {
    var description: String?
    var files: [String: GistFileBody]
}

/// One file in a create/update body. `content: nil` deletes the file
/// on update.
private struct GistFileBody: Encodable {
    var content: String?
}

/// `POST /gists/{id}/comments`.
private struct GistCommentBody: Encodable {
    var body: String
}
