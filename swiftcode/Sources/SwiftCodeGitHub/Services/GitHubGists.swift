import Foundation

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
    public var gitPushUrl: String?
    public var gitPullUrl: String?
    public var history: [GitHubGistRevision]

    public var sortedFiles: [GitHubGistFile] {
        files.values.sorted { $0.filename < $1.filename }
    }

    private enum CodingKeys: String, CodingKey {
        case id, description, owner, files, comments, createdAt, updatedAt, htmlUrl, history, gitPushUrl, gitPullUrl
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
        gitPushUrl = try container.decodeIfPresent(String.self, forKey: .gitPushUrl)
        gitPullUrl = try container.decodeIfPresent(String.self, forKey: .gitPullUrl)
        history = try container.decodeIfPresent([GitHubGistRevision].self, forKey: .history) ?? []
        let rawFiles = try container.decodeIfPresent([String: GitHubGistFile].self, forKey: .files) ?? [:]
        var filled: [String: GitHubGistFile] = [:]
        for (key, var file) in rawFiles {
            if file.filename.isEmpty { file.filename = key }
            filled[key] = file
        }
        files = filled
    }
}

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

public struct GitHubGistComment: Sendable, Equatable, Decodable, Identifiable {
    public var id: Int
    public var body: String
    public var user: GitHubUser?
    public var createdAt: Date?
    public var updatedAt: Date?
}

public struct GitHubGistRevision: Sendable, Equatable, Decodable, Identifiable {
    public var id: String { version }
    public var version: String
    public var user: GitHubUser?
    public var committedAt: Date?
    public var changeStatus: GitHubGistChangeStatus?

    private enum CodingKeys: String, CodingKey {
        case version, user, committedAt, changeStatus
    }
}

public struct GitHubGistChangeStatus: Sendable, Equatable, Decodable {
    public var additions: Int
    public var deletions: Int
    public var total: Int
}

public struct GitHubGistClient: Sendable {
    private let transport: GitHubRESTTransport

    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { nil }) {
        self.transport = GitHubRESTTransport(session: session, tokenProvider: tokenProvider)
    }

    public func listGists(perPage: Int = 30, page: Int = 1) async throws -> [GitHubGist] {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        return try await transport.perform(transport.request(
            path: "gists",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))"),
                    URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    public func listStarredGists(perPage: Int = 30, page: Int = 1) async throws -> [GitHubGist] {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        return try await transport.perform(transport.request(
            path: "gists/starred",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))"),
                    URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

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

    public func fetchGist(id: String) async throws -> GitHubGist {
        let gistId = try validatedId(id)
        return try await transport.perform(transport.request(path: "gists/\(transport.encode(gistId))"))
    }

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

    public func deleteGist(id: String) async throws {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let gistId = try validatedId(id)
        try await transport.performVoid(transport.request(path: "gists/\(transport.encode(gistId))", method: "DELETE"))
    }

    public func isStarred(id: String) async throws -> Bool {
        let gistId = try validatedId(id)
        do {
            try await transport.performVoid(transport.request(path: "gists/\(transport.encode(gistId))/star"))
            return true
        } catch GitHubError.notFound {
            return false
        }
    }

    public func starGist(id: String) async throws {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let gistId = try validatedId(id)
        try await transport.performVoid(transport.request(path: "gists/\(transport.encode(gistId))/star", method: "PUT"))
    }

    public func unstarGist(id: String) async throws {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let gistId = try validatedId(id)
        try await transport.performVoid(transport.request(path: "gists/\(transport.encode(gistId))/star", method: "DELETE"))
    }

    public func fetchComments(gistId: String) async throws -> [GitHubGistComment] {
        let id = try validatedId(gistId)
        return try await transport.perform(transport.request(path: "gists/\(transport.encode(id))/comments"))
    }

    public func createComment(gistId: String, body: String) async throws -> GitHubGistComment {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let id = try validatedId(gistId)
        let payload = try transport.jsonBody(GistCommentBody(body: body))
        return try await transport.perform(transport.request(path: "gists/\(transport.encode(id))/comments", method: "POST", body: payload))
    }

    public func fetchRevisions(gistId: String) async throws -> [GitHubGistRevision] {
        let gist = try await fetchGist(id: gistId)
        return gist.history
    }

    public func fetchGistAtRevision(id: String, sha: String) async throws -> GitHubGist {
        let gistId = try validatedId(id)
        let revision = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty else {
            throw GitHubError.unprocessable(message: "A revision SHA is required")
        }
        return try await transport.perform(transport.request(
            path: "gists/\(transport.encode(gistId))/\(transport.encode(revision))"))
    }

    public func forkGist(id: String) async throws -> GitHubGist {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let gistId = try validatedId(id)
        return try await transport.perform(transport.request(path: "gists/\(transport.encode(gistId))/forks", method: "POST"))
    }

    public func cloneURL(for gist: GitHubGist, useSSH: Bool) -> String {
        if useSSH {
            if let push = gist.gitPushUrl, !push.isEmpty {
                return push
            }
            return "git@gist.github.com:\(gist.id).git"
        }
        if let pull = gist.gitPullUrl, !pull.isEmpty {
            return pull
        }
        return "https://gist.github.com/\(gist.id).git"
    }

    public func uploadFilesToGist(id: String, urls: [URL]) async throws -> GitHubGist {
        guard !(transport.tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        var imported: [String: String?] = [:]
        for url in urls {
            for entry in try collectFileEntries(from: url) {
                imported[entry.name] = entry.content
            }
        }
        guard !imported.isEmpty else {
            throw GitHubError.unprocessable(message: "No readable files found in selection.")
        }
        return try await updateGist(id: id, description: nil, files: imported)
    }

    public func downloadGistZip(gistId: String) async throws -> URL {
        let gist = try await fetchGist(id: gistId)
        let revision = gist.history.first?.version ?? "HEAD"
        guard let zipURL = URL(string: "https://gist.github.com/\(gist.id)/archive/\(revision).zip") else {
            throw GitHubError.unprocessable(message: "Invalid Gist URL for download")
        }
        var request = URLRequest(url: zipURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = transport.tokenProvider(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GitHubError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Failed to download ZIP archive")
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(gistId)-\(revision).zip")
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private func collectFileEntries(from url: URL) throws -> [(name: String, content: String)] {
        let needsScoped = url.startAccessingSecurityScopedResource()
        defer { if needsScoped { url.stopAccessingSecurityScopedResource() } }

        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var output: [(name: String, content: String)] = []
            while let item = enumerator?.nextObject() as? URL {
                let itemValues = try item.resourceValues(forKeys: [.isDirectoryKey])
                guard itemValues.isDirectory != true else { continue }
                if let content = try? String(contentsOf: item) {
                    output.append((item.lastPathComponent, content))
                }
            }
            return output
        }

        guard let content = try? String(contentsOf: url) else { return [] }
        return [(url.lastPathComponent, content)]
    }

    private func validatedId(_ id: String) throws -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            throw GitHubError.unprocessable(message: "A gist ID is required")
        }
        return trimmed
    }
}

private struct GistCreateBody: Encodable {
    var description: String?
    var isPublic: Bool
    var files: [String: GistFileBody]

    private enum CodingKeys: String, CodingKey {
        case description, files
        case isPublic = "public"
    }
}

private struct GistUpdateBody: Encodable {
    var description: String?
    var files: [String: GistFileBody]
}

private struct GistFileBody: Encodable {
    var content: String?
}

private struct GistCommentBody: Encodable {
    var body: String
}
