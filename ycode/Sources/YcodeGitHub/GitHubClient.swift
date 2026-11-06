import Foundation

/// The api.github.com client the assistant's GitHub tools and the settings
/// pane share. The token is optional: unauthenticated requests work for
/// public reads at GitHub's lower rate limit. The token itself is never
/// stored here — `tokenProvider` reads it from the secret store on each
/// request — and it is never logged.
public struct GitHubClient: Sendable {
    /// The base URL is not configurable: GitHub's API lives here.
    public static let baseURL = URL(string: "https://api.github.com")!

    private static let apiVersion = "2022-11-28"
    private static let userAgent = "Ycode"
    private static let accept = "application/vnd.github+json"

    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?
    private let rateLimitBox = RateLimitBox()

    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { nil }) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    /// The rate-limit state from the most recent response, if it carried
    /// rate-limit headers. Updated after every response, success or error.
    /// The setter is non-mutating: the state lives in the locked box, so
    /// non-mutating async methods can record it.
    public private(set) var lastRateLimit: GitHubRateLimit? {
        get { rateLimitBox.value }
        nonmutating set { rateLimitBox.value = newValue }
    }

    // MARK: - Rate limit

    /// `GET /rate_limit`: the caller's current core rate-limit state.
    public func rateLimit() async throws -> GitHubRateLimit {
        let response: RateLimitResponse = try await perform(request(path: "rate_limit"))
        lastRateLimit = response.rate
        return response.rate
    }

    // MARK: - Users and repositories

    /// `GET /user`. Requires a token.
    public func getAuthenticatedUser() async throws -> GitHubUser {
        guard !(tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        return try await perform(request(path: "user"))
    }

    /// `GET /repos/{owner}/{repo}`.
    public func getRepository(owner: String, repo: String) async throws -> GitHubRepository {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))"))
    }

    /// `GET /repos/{owner}/{repo}/branches`.
    public func listBranches(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubBranch] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/branches",
                                        query: [URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    /// `GET /repos/{owner}/{repo}/commits?sha={branch}`.
    public func listCommits(owner: String, repo: String, branch: String = "main", perPage: Int = 20) async throws -> [GitHubCommit] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/commits",
                                        query: [URLQueryItem(name: "sha", value: branch),
                                                URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    // MARK: - Files and trees

    /// `GET /repos/{owner}/{repo}/contents/{path}` (optionally at `ref`).
    public func getFileContent(owner: String, repo: String, path: String, ref: String? = nil) async throws -> GitHubFileContent {
        try validateRepo(owner: owner, repo: repo)
        var query: [URLQueryItem] = []
        if let ref { query.append(URLQueryItem(name: "ref", value: ref)) }
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/contents/\(encode(path))", query: query))
    }

    /// The decoded text of a file: `getFileContent` with its base64
    /// content decoded (the API wraps lines, so newlines are stripped
    /// first). Throws `.decoding` when the content is not valid base64
    /// or not UTF-8.
    public func getFileText(owner: String, repo: String, path: String, ref: String? = nil) async throws -> String {
        let file = try await getFileContent(owner: owner, repo: repo, path: path, ref: ref)
        let cleaned = file.content.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: cleaned),
              let text = String(data: data, encoding: .utf8) else {
            throw GitHubError.decoding
        }
        return text
    }

    /// `GET /repos/{owner}/{repo}/git/trees/{ref}?recursive=1`.
    public func getRepoTree(owner: String, repo: String, ref: String = "main", recursive: Bool = true) async throws -> [GitHubTreeEntry] {
        try validateRepo(owner: owner, repo: repo)
        let response: TreeResponse = try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/git/trees/\(encode(ref))",
                                                              query: [URLQueryItem(name: "recursive", value: recursive ? "1" : "0")]))
        return response.tree
    }

    // MARK: - Issues

    /// `GET /repos/{owner}/{repo}/issues`. Pull requests also appear
    /// here (with `isPullRequest` set); pass `state` "open", "closed"
    /// or "all".
    public func listIssues(owner: String, repo: String, state: String = "open", perPage: Int = 30, page: Int = 1) async throws -> [GitHubIssue] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/issues",
                                        query: [URLQueryItem(name: "state", value: state),
                                                URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))"),
                                                URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    /// `GET /repos/{owner}/{repo}/issues/{number}`.
    public func getIssue(owner: String, repo: String, number: Int) async throws -> GitHubIssue {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/issues/\(number)"))
    }

    /// `POST /repos/{owner}/{repo}/issues`.
    public func createIssue(owner: String, repo: String, title: String, body: String?, labels: [String] = []) async throws -> GitHubIssue {
        try validateRepo(owner: owner, repo: repo)
        let payload = try jsonBody(IssueCreateBody(title: title, body: body, labels: labels))
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/issues", method: "POST", body: payload))
    }

    /// `PATCH /repos/{owner}/{repo}/issues/{number}`. Only non-nil
    /// fields are sent; the rest are left alone.
    public func updateIssue(owner: String, repo: String, number: Int, title: String?, body: String?, state: String?) async throws -> GitHubIssue {
        try validateRepo(owner: owner, repo: repo)
        let payload = try jsonBody(IssueUpdateBody(title: title, body: body, state: state))
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/issues/\(number)", method: "PATCH", body: payload))
    }

    /// `GET /search/issues?q={query}`.
    public func searchIssues(query: String, perPage: Int = 30, page: Int = 1) async throws -> GitHubSearchResult<GitHubIssue> {
        try await perform(request(path: "search/issues",
                                  query: [URLQueryItem(name: "q", value: query),
                                          URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))"),
                                          URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    // MARK: - Pull requests

    /// `GET /repos/{owner}/{repo}/pulls/{number}`.
    public func getPullRequest(owner: String, repo: String, number: Int) async throws -> GitHubPullRequest {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls/\(number)"))
    }

    /// `GET /repos/{owner}/{repo}/pulls`.
    public func listPullRequests(owner: String, repo: String, state: String = "open", perPage: Int = 30) async throws -> [GitHubPullRequest] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls",
                                        query: [URLQueryItem(name: "state", value: state),
                                                URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    /// `POST /repos/{owner}/{repo}/pulls`.
    public func createPullRequest(owner: String, repo: String, title: String, body: String?, head: String, base: String, draft: Bool = false) async throws -> GitHubPullRequest {
        try validateRepo(owner: owner, repo: repo)
        let payload = try jsonBody(PullRequestCreateBody(title: title, body: body, head: head, base: base, draft: draft))
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls", method: "POST", body: payload))
    }

    /// `GET /repos/{owner}/{repo}/pulls/{number}/files`.
    public func listPullRequestFiles(owner: String, repo: String, number: Int) async throws -> [GitHubPullRequestFile] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls/\(number)/files"))
    }

    /// `GET /repos/{owner}/{repo}/pulls/{number}/reviews`.
    public func listPullRequestReviews(owner: String, repo: String, number: Int) async throws -> [GitHubReview] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls/\(number)/reviews"))
    }

    /// `GET /search/code?q={query}`.
    public func searchCode(query: String, perPage: Int = 30) async throws -> GitHubSearchResult<GitHubCodeItem> {
        try await perform(request(path: "search/code",
                                  query: [URLQueryItem(name: "q", value: query),
                                          URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    // MARK: - Request machinery

    private func request(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        // `path` is already percent-encoded segment by segment, so set
        // the encoded path directly (a plain `path` set would re-encode
        // the `%` escapes).
        components.percentEncodedPath = "/" + path
        if !query.isEmpty { components.queryItems = query }
        // Every component is percent-encoded by construction, so the URL
        // always builds.
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method
        urlRequest.setValue(Self.accept, forHTTPHeaderField: "Accept")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let token = tokenProvider(), !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    /// Sends the request, records the rate-limit headers, maps the
    /// status, and decodes the body.
    private func perform<T: Decodable>(_ urlRequest: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw GitHubError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.network
        }
        recordRateLimit(from: http)
        try validate(http, data: data)
        do {
            return try Self.decoder().decode(T.self, from: data)
        } catch {
            throw GitHubError.decoding
        }
    }

    private func recordRateLimit(from http: HTTPURLResponse) {
        let parsed = GitHubRateLimit.parse(from: http)
        // Only replace what the response actually said: a response with
        // no rate-limit headers leaves the last known state alone.
        if parsed.limit != nil || parsed.remaining != nil || parsed.resetAt != nil || parsed.retryAfter != nil {
            lastRateLimit = parsed
        }
    }

    private func validate(_ http: HTTPURLResponse, data: Data) throws {
        guard (200...299).contains(http.statusCode) else {
            throw error(for: http, data: data)
        }
    }

    private func error(for http: HTTPURLResponse, data: Data) -> GitHubError {
        let message = Self.githubMessage(from: data)
        let rate = GitHubRateLimit.parse(from: http)
        switch http.statusCode {
        case 401:
            return .unauthorized
        case 404:
            return .notFound
        case 422:
            return .unprocessable(message: message ?? "Unprocessable entity")
        case 403:
            // Exhausted quota, or GitHub saying so in the message (the
            // headers are sometimes absent on secondary limits).
            let exhausted = rate.isExhausted || (message?.lowercased().contains("rate limit") ?? false)
            if exhausted {
                return .forbidden(message: message ?? "Rate limit exceeded", rateLimited: true, resetAt: rate.resetAt)
            }
            return .forbidden(message: message ?? "Forbidden", rateLimited: false, resetAt: nil)
        case 429:
            return .forbidden(message: message ?? "Rate limit exceeded", rateLimited: true, resetAt: rate.resetAt)
        default:
            return .http(status: http.statusCode, message: message ?? "HTTP \(http.statusCode)")
        }
    }

    /// GitHub's error JSON: `{"message": "...", ...}`.
    private static func githubMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else {
            return nil
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func jsonBody<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw GitHubError.decoding
        }
    }

    /// `per_page` must be 1...100 on the GitHub API.
    private func clampedPerPage(_ perPage: Int) -> Int {
        min(100, max(1, perPage))
    }

    private func validateRepo(owner: String, repo: String) throws {
        let owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repo.isEmpty,
              !owner.contains("/"), !repo.contains("/") else {
            throw GitHubError.invalidRepo("\(owner)/\(repo)")
        }
    }

    /// Percent-encodes one path segment (or a whole file path: `/`
    /// stays a separator, as in Legacy).
    private func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

// MARK: - Private helpers

/// The rate-limit state behind `lastRateLimit`. The client is a struct,
/// so its mutable state lives in a locked box and stays `Sendable`.
private final class RateLimitBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: GitHubRateLimit?

    var value: GitHubRateLimit? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// `GET /rate_limit` wraps the state in a `rate` object.
private struct RateLimitResponse: Decodable {
    var rate: GitHubRateLimit
}

/// `GET /repos/{owner}/{repo}/git/trees/{ref}` wraps the entries in `tree`.
private struct TreeResponse: Decodable {
    var tree: [GitHubTreeEntry]
}

/// `POST /repos/{owner}/{repo}/issues`. Nil fields are omitted.
private struct IssueCreateBody: Encodable {
    var title: String
    var body: String?
    var labels: [String]
}

/// `PATCH /repos/{owner}/{repo}/issues/{number}`. Nil fields are omitted,
/// so only the fields the caller set are sent.
private struct IssueUpdateBody: Encodable {
    var title: String?
    var body: String?
    var state: String?
}

/// `POST /repos/{owner}/{repo}/pulls`. Nil fields are omitted.
private struct PullRequestCreateBody: Encodable {
    var title: String
    var body: String?
    var head: String
    var base: String
    var draft: Bool
}
