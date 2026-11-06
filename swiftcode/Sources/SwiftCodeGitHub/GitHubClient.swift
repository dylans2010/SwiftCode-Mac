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
    private static let userAgent = "SwiftCode"
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

    /// `GET /repos/{owner}/{repo}/contents/{path}` returning only
    /// the blob SHA, or nil when the file does not exist (HTTP 404).
    /// Other failures throw, as in the rest of the client — Legacy
    /// returned nil for every non-200 status, which would have
    /// hidden an expired token as "file does not exist"; this port
    /// only treats 404 as missing. Used to decide whether
    /// `pushFile` creates or updates.
    public func getFileSHA(owner: String, repo: String, path: String) async throws -> String? {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/contents/\(encode(path))"))
        if http.statusCode == 404 { return nil }
        try validate(http, data: data)
        do {
            return try Self.decoder().decode(GitHubFileContent.self, from: data).sha
        } catch {
            throw GitHubError.decoding
        }
    }

    /// `PUT /repos/{owner}/{repo}/contents/{path}`: creates the
    /// file, or updates it when `sha` is the blob SHA of the
    /// current version (fetch it with `getFileSHA` first). The
    /// content is base64-encoded by this method; callers pass plain
    /// text. Returns the created/updated file. Pass `branch` to
    /// target a branch other than the default (Legacy had no branch
    /// parameter; the API supports it, so it is additive here).
    /// Writes need `contents: write` on a fine-grained token, or
    /// the classic `repo` scope.
    public func pushFile(owner: String, repo: String, path: String, content: String, message: String, sha: String? = nil, branch: String? = nil) async throws -> GitHubFileContent {
        try validateRepo(owner: owner, repo: repo)
        let payload = try jsonBody(PutFileBody(
            message: message,
            content: Data(content.utf8).base64EncodedString(),
            sha: sha,
            branch: branch))
        let response: ContentsResponse = try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/contents/\(encode(path))",
            method: "PUT", body: payload))
        return response.content
    }

    // MARK: - Workflow runs, jobs, artifacts

    /// `GET /repos/{owner}/{repo}/actions/runs`. Public
    /// repositories are readable without a token; private ones need
    /// `actions: read` (fine-grained) or the classic `repo` scope.
    public func listWorkflowRuns(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubWorkflowRun] {
        try validateRepo(owner: owner, repo: repo)
        let response: WorkflowRunsResponse = try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/actions/runs",
            query: [URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
        return response.workflowRuns
    }

    /// `GET /repos/{owner}/{repo}/actions/runs/{run_id}`.
    public func getWorkflowRun(owner: String, repo: String, runID: Int) async throws -> GitHubWorkflowRun {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/actions/runs/\(runID)"))
    }

    /// `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs`.
    public func listWorkflowJobs(owner: String, repo: String, runID: Int) async throws -> [GitHubWorkflowJob] {
        try validateRepo(owner: owner, repo: repo)
        let response: WorkflowJobsResponse = try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/actions/runs/\(runID)/jobs"))
        return response.jobs
    }

    /// `GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs`: the
    /// log text. `URLSession` follows GitHub's redirect to the
    /// temporary download URL automatically; the returned string is
    /// the log (UTF-8, falling back to empty, as in Legacy).
    public func getJobLogs(owner: String, repo: String, jobID: Int) async throws -> String {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/actions/jobs/\(jobID)/logs"))
        try validate(http, data: data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// `GET /repos/{owner}/{repo}/actions/runs/{run_id}/logs`: the
    /// temporary download URL for the run's logs. GitHub answers
    /// with a 302 to a short-lived URL; `URLSession` follows the
    /// redirect and the final URL is returned (Legacy stopped at
    /// the 302 with a no-redirect delegate to avoid downloading
    /// the logs — this port follows it and returns the same URL,
    /// at the cost of downloading the log body once).
    public func getWorkflowRunLogsURL(owner: String, repo: String, runID: Int) async throws -> URL {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/actions/runs/\(runID)/logs"))
        try validate(http, data: data)
        guard let url = http.url else {
            throw GitHubError.http(status: http.statusCode, message: "GitHub returned no logs URL.")
        }
        return url
    }

    /// `GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts`.
    public func listWorkflowArtifacts(owner: String, repo: String, runID: Int) async throws -> [GitHubArtifact] {
        try validateRepo(owner: owner, repo: repo)
        let response: GitHubArtifactsResponse = try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/actions/runs/\(runID)/artifacts"))
        return response.artifacts
    }

    /// `GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}/zip`:
    /// the artifact's ZIP bytes. The caller decides where to save
    /// them.
    public func downloadArtifact(owner: String, repo: String, artifactID: Int) async throws -> Data {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/actions/artifacts/\(artifactID)/zip"))
        try validate(http, data: data)
        return data
    }

    // MARK: - Releases

    /// `GET /repos/{owner}/{repo}/releases`.
    public func listReleases(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubRelease] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/releases",
                                        query: [URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    // MARK: - Repository archive and creation

    /// `GET /repos/{owner}/{repo}/zipball/{branch}`: the
    /// repository's ZIP bytes. Legacy wrote them straight to the
    /// user's Documents folder; this client returns the bytes and
    /// the caller chooses where to save them.
    public func downloadRepositoryZip(owner: String, repo: String, branch: String = "main") async throws -> Data {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/zipball/\(encode(branch))"))
        try validate(http, data: data)
        return data
    }

    /// `POST /user/repos`: creates a repository under the
    /// authenticated user. Needs `public_repo` (public repos) or
    /// `repo` (private repos) on a classic token, or
    /// `administration: write` on a fine-grained token. Returns
    /// the created repository.
    public func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepository {
        guard !(tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let payload = try jsonBody(CreateRepositoryBody(
            name: name, description: description, isPrivate: isPrivate, autoInit: false))
        return try await perform(request(path: "user/repos", method: "POST", body: payload))
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
        let (data, http) = try await performRaw(urlRequest)
        try validate(http, data: data)
        do {
            return try Self.decoder().decode(T.self, from: data)
        } catch {
            throw GitHubError.decoding
        }
    }

    /// Sends the request and returns the raw bytes plus the HTTP
    /// response: for endpoints whose answer is not JSON (log text,
    /// ZIP bytes) or whose status the caller inspects itself
    /// (`getFileSHA` treats 404 as "missing"). Records the
    /// rate-limit headers but does NOT map the status — every
    /// caller validates with `validate(_:data:)` (or checks the
    /// status itself first) before using the bytes.
    private func performRaw(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
        return (data, http)
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

/// `PUT /repos/{owner}/{repo}/contents/{path}`. `sha` and `branch`
/// are omitted when nil, so a create sends only `message` +
/// `content` and an update adds the current blob SHA.
private struct PutFileBody: Encodable {
    var message: String
    var content: String
    var sha: String?
    var branch: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(sha, forKey: .sha)
        try container.encodeIfPresent(branch, forKey: .branch)
    }

    private enum CodingKeys: String, CodingKey {
        case message, content, sha, branch
    }
}

/// `PUT /repos/{owner}/{repo}/contents/{path}` answers
/// `{"content": {...}, "commit": {...}}`.
private struct ContentsResponse: Decodable {
    var content: GitHubFileContent
}

/// `POST /user/repos`. Legacy sent `auto_init: false` too, kept here.
private struct CreateRepositoryBody: Encodable {
    var name: String
    var description: String
    var isPrivate: Bool
    var autoInit: Bool

    private enum CodingKeys: String, CodingKey {
        case name, description
        case isPrivate = "private"
        case autoInit = "auto_init"
    }
}

/// `GET /repos/{owner}/{repo}/actions/runs` wraps the runs in
/// `workflow_runs`.
private struct WorkflowRunsResponse: Decodable {
    var workflowRuns: [GitHubWorkflowRun]
}

/// `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs` wraps the
/// jobs in `jobs`.
private struct WorkflowJobsResponse: Decodable {
    var jobs: [GitHubWorkflowJob]
}

/// `GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts`
/// wraps the artifacts in `artifacts`.
private struct GitHubArtifactsResponse: Decodable {
    var artifacts: [GitHubArtifact]
}
