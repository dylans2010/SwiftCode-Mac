import Foundation

public struct GitHubClient: Sendable {
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

    public private(set) var lastRateLimit: GitHubRateLimit? {
        get { rateLimitBox.value }
        nonmutating set { rateLimitBox.value = newValue }
    }

    public func rateLimit() async throws -> GitHubRateLimit {
        let response: RateLimitResponse = try await perform(request(path: "rate_limit"))
        lastRateLimit = response.rate
        return response.rate
    }

    public func getAuthenticatedUser() async throws -> GitHubUser {
        guard !(tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        return try await perform(request(path: "user"))
    }

    public func getRepository(owner: String, repo: String) async throws -> GitHubRepository {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))"))
    }

    public func listBranches(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubBranch] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/branches",
                                        query: [URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    public func listCommits(owner: String, repo: String, branch: String = "main", perPage: Int = 20) async throws -> [GitHubCommit] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/commits",
                                        query: [URLQueryItem(name: "sha", value: branch),
                                                URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    public func getFileContent(owner: String, repo: String, path: String, ref: String? = nil) async throws -> GitHubFileContent {
        try validateRepo(owner: owner, repo: repo)
        var query: [URLQueryItem] = []
        if let ref { query.append(URLQueryItem(name: "ref", value: ref)) }
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/contents/\(encode(path))", query: query))
    }

    public func getFileText(owner: String, repo: String, path: String, ref: String? = nil) async throws -> String {
        let file = try await getFileContent(owner: owner, repo: repo, path: path, ref: ref)
        let cleaned = file.content.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: cleaned),
              let text = String(data: data, encoding: .utf8) else {
            throw GitHubError.decoding
        }
        return text
    }

    public func getRepoTree(owner: String, repo: String, ref: String = "main", recursive: Bool = true) async throws -> [GitHubTreeEntry] {
        try validateRepo(owner: owner, repo: repo)
        let response: TreeResponse = try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/git/trees/\(encode(ref))",
                                                              query: [URLQueryItem(name: "recursive", value: recursive ? "1" : "0")]))
        return response.tree
    }

    public func createBranch(owner: String, repo: String, branch: String, from baseBranch: String = "main") async throws {
        try validateRepo(owner: owner, repo: repo)
        struct RefResponse: Decodable { struct Object: Decodable { var sha: String }; var object: Object }
        let base: RefResponse = try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/git/ref/heads/\(encode(baseBranch))"))
        struct CreateRefBody: Encodable { var ref: String; var sha: String }
        let payload = try jsonBody(CreateRefBody(ref: "refs/heads/\(branch)", sha: base.object.sha))
        let _: RefResponse = try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/git/refs", method: "POST", body: payload))
    }

    public func getFileSHA(owner: String, repo: String, path: String, ref: String? = nil) async throws -> String? {
        try validateRepo(owner: owner, repo: repo)
        let query = ref.map { [URLQueryItem(name: "ref", value: $0)] } ?? []
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/contents/\(encode(path))", query: query))
        if http.statusCode == 404 { return nil }
        try validate(http, data: data)
        do {
            return try Self.decoder().decode(GitHubFileContent.self, from: data).sha
        } catch {
            throw GitHubError.decoding
        }
    }

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

    public func listWorkflows(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubWorkflow] {
        try validateRepo(owner: owner, repo: repo)
        let response: WorkflowsResponse = try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/actions/workflows",
            query: [URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
        return response.workflows
    }

    public func rerunWorkflow(owner: String, repo: String, runID: Int) async throws {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(
            path: "repos/\(encode(owner))/\(encode(repo))/actions/runs/\(runID)/rerun",
            method: "POST"))
        try validate(http, data: data)
    }

    public func listWorkflowRuns(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubWorkflowRun] {
        try validateRepo(owner: owner, repo: repo)
        let response: WorkflowRunsResponse = try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/actions/runs",
            query: [URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
        return response.workflowRuns
    }

    public func getWorkflowRun(owner: String, repo: String, runID: Int) async throws -> GitHubWorkflowRun {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/actions/runs/\(runID)"))
    }

    public func listWorkflowJobs(owner: String, repo: String, runID: Int) async throws -> [GitHubWorkflowJob] {
        try validateRepo(owner: owner, repo: repo)
        let response: WorkflowJobsResponse = try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/actions/runs/\(runID)/jobs"))
        return response.jobs
    }

    public func getJobLogs(owner: String, repo: String, jobID: Int) async throws -> String {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/actions/jobs/\(jobID)/logs"))
        try validate(http, data: data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func getWorkflowRunLogsURL(owner: String, repo: String, runID: Int) async throws -> URL {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/actions/runs/\(runID)/logs"))
        try validate(http, data: data)
        guard let url = http.url else {
            throw GitHubError.http(status: http.statusCode, message: "GitHub returned no logs URL.")
        }
        return url
    }

    public func listWorkflowArtifacts(owner: String, repo: String, runID: Int) async throws -> [GitHubArtifact] {
        try validateRepo(owner: owner, repo: repo)
        let response: GitHubArtifactsResponse = try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/actions/runs/\(runID)/artifacts"))
        return response.artifacts
    }

    public func downloadArtifact(owner: String, repo: String, artifactID: Int) async throws -> Data {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/actions/artifacts/\(artifactID)/zip"))
        try validate(http, data: data)
        return data
    }

    public func getPagesInfo(owner: String, repo: String) async throws -> GitHubPagesInfo {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pages"))
    }

    public func enablePages(owner: String, repo: String) async throws -> GitHubPagesInfo {
        try validateRepo(owner: owner, repo: repo)
        let payload = try jsonBody(EnablePagesBody(buildType: "workflow"))
        return try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/pages",
            method: "POST", body: payload))
    }

    public func listPagesDeployments(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubPagesDeployment] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(
            path: "repos/\(encode(owner))/\(encode(repo))/pages/deployments",
            query: [URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    public func listReleases(owner: String, repo: String, perPage: Int = 30) async throws -> [GitHubRelease] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/releases",
                                        query: [URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    public func downloadRepositoryZip(owner: String, repo: String, branch: String = "main") async throws -> Data {
        try validateRepo(owner: owner, repo: repo)
        let (data, http) = try await performRaw(request(path: "repos/\(encode(owner))/\(encode(repo))/zipball/\(encode(branch))"))
        try validate(http, data: data)
        return data
    }

    public func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepository {
        guard !(tokenProvider() ?? "").isEmpty else {
            throw GitHubError.missingToken
        }
        let payload = try jsonBody(CreateRepositoryBody(
            name: name, description: description, isPrivate: isPrivate, autoInit: false))
        return try await perform(request(path: "user/repos", method: "POST", body: payload))
    }

    public func listIssues(owner: String, repo: String, state: String = "open", perPage: Int = 30, page: Int = 1) async throws -> [GitHubIssue] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/issues",
                                        query: [URLQueryItem(name: "state", value: state),
                                                URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))"),
                                                URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    public func getIssue(owner: String, repo: String, number: Int) async throws -> GitHubIssue {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/issues/\(number)"))
    }

    public func createIssue(owner: String, repo: String, title: String, body: String?, labels: [String] = []) async throws -> GitHubIssue {
        try validateRepo(owner: owner, repo: repo)
        let payload = try jsonBody(IssueCreateBody(title: title, body: body, labels: labels))
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/issues", method: "POST", body: payload))
    }

    public func updateIssue(owner: String, repo: String, number: Int, title: String?, body: String?, state: String?) async throws -> GitHubIssue {
        try validateRepo(owner: owner, repo: repo)
        let payload = try jsonBody(IssueUpdateBody(title: title, body: body, state: state))
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/issues/\(number)", method: "PATCH", body: payload))
    }

    public func searchIssues(query: String, perPage: Int = 30, page: Int = 1) async throws -> GitHubSearchResult<GitHubIssue> {
        try await perform(request(path: "search/issues",
                                  query: [URLQueryItem(name: "q", value: query),
                                          URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))"),
                                          URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    public func getPullRequest(owner: String, repo: String, number: Int) async throws -> GitHubPullRequest {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls/\(number)"))
    }

    public func listPullRequests(owner: String, repo: String, state: String = "open", perPage: Int = 30) async throws -> [GitHubPullRequest] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls",
                                        query: [URLQueryItem(name: "state", value: state),
                                                URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    public func createPullRequest(owner: String, repo: String, title: String, body: String?, head: String, base: String, draft: Bool = false) async throws -> GitHubPullRequest {
        try validateRepo(owner: owner, repo: repo)
        let payload = try jsonBody(PullRequestCreateBody(title: title, body: body, head: head, base: base, draft: draft))
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls", method: "POST", body: payload))
    }

    public func listPullRequestFiles(owner: String, repo: String, number: Int) async throws -> [GitHubPullRequestFile] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls/\(number)/files"))
    }

    public func listPullRequestReviews(owner: String, repo: String, number: Int) async throws -> [GitHubReview] {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/pulls/\(number)/reviews"))
    }

    public func searchCode(query: String, perPage: Int = 30) async throws -> GitHubSearchResult<GitHubCodeItem> {
        try await perform(request(path: "search/code",
                                  query: [URLQueryItem(name: "q", value: query),
                                          URLQueryItem(name: "per_page", value: "\(clampedPerPage(perPage))")]))
    }

    private func request(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/" + path
        if !query.isEmpty { components.queryItems = query }
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

    private func perform<T: Decodable>(_ urlRequest: URLRequest) async throws -> T {
        let (data, http) = try await performRaw(urlRequest)
        try validate(http, data: data)
        do {
            return try Self.decoder().decode(T.self, from: data)
        } catch {
            throw GitHubError.decoding
        }
    }

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

    private func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private final class RateLimitBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: GitHubRateLimit?

    var value: GitHubRateLimit? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

private struct RateLimitResponse: Decodable {
    var rate: GitHubRateLimit
}

private struct TreeResponse: Decodable {
    var tree: [GitHubTreeEntry]
}

private struct IssueCreateBody: Encodable {
    var title: String
    var body: String?
    var labels: [String]
}

private struct IssueUpdateBody: Encodable {
    var title: String?
    var body: String?
    var state: String?
}

private struct PullRequestCreateBody: Encodable {
    var title: String
    var body: String?
    var head: String
    var base: String
    var draft: Bool
}

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

private struct ContentsResponse: Decodable {
    var content: GitHubFileContent
}

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

private struct WorkflowRunsResponse: Decodable {
    var workflowRuns: [GitHubWorkflowRun]
}

private struct WorkflowJobsResponse: Decodable {
    var jobs: [GitHubWorkflowJob]
}

private struct GitHubArtifactsResponse: Decodable {
    var artifacts: [GitHubArtifact]
}

private struct WorkflowsResponse: Decodable {
    var workflows: [GitHubWorkflow]
}

private struct EnablePagesBody: Encodable {
    var buildType: String

    private enum CodingKeys: String, CodingKey {
        case buildType = "build_type"
    }
}

extension GitHubClient {
    public func listLanguages(owner: String, repo: String) async throws -> [String] {
        try validateRepo(owner: owner, repo: repo)
        let counts: [String: Int] = try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/languages"))
        return counts.keys.sorted { counts[$0, default: 0] > counts[$1, default: 0] }
    }

    public func forkRepository(owner: String, repo: String) async throws -> GitHubRepository {
        try validateRepo(owner: owner, repo: repo)
        return try await perform(request(path: "repos/\(encode(owner))/\(encode(repo))/forks", method: "POST"))
    }

    public func starRepository(owner: String, repo: String, starred: Bool) async throws {
        try validateRepo(owner: owner, repo: repo)
        let (_, http) = try await performRaw(request(path: "user/starred/\(encode(owner))/\(encode(repo))",
                                                    method: starred ? "PUT" : "DELETE"))
        try validate(http, data: Data())
    }

    public func isRepositoryStarred(owner: String, repo: String) async throws -> Bool {
        try validateRepo(owner: owner, repo: repo)
        let (_, http) = try await performRaw(request(path: "user/starred/\(encode(owner))/\(encode(repo))"))
        switch http.statusCode {
        case 204: return true
        case 404: return false
        default:
            try validate(http, data: Data())
            return false
        }
    }
}
