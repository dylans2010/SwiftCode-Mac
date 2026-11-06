import Foundation
import Testing
@testable import SwiftCodeGitHub

// All fixtures are synthetic: made-up users, repositories and issues.
// No real token is used anywhere; the stub token is a placeholder.

// MARK: - Stub transport

/// A URLProtocol stub: the handler answers every request from canned
/// data, and every request the client made is recorded for assertions.
/// No live network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, headers: [String: String], body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func stubClient(token: String? = "test-token",
                handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)) -> GitHubClient {
    StubURLProtocol.requests = []
    StubURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return GitHubClient(session: URLSession(configuration: config), tokenProvider: { token })
}

func json(_ string: String) -> Data { Data(string.utf8) }

func ok(_ body: String, headers: [String: String] = [:]) -> (status: Int, headers: [String: String], body: Data) {
    (200, headers, json(body))
}

func error(_ status: Int, message: String, headers: [String: String] = [:]) -> (status: Int, headers: [String: String], body: Data) {
    (status, headers, json("{\"message\":\"\(message)\",\"documentation_url\":\"https://docs.github.com\"}"))
}

let rateHeaders = ["X-RateLimit-Limit": "60", "X-RateLimit-Remaining": "59", "X-RateLimit-Reset": "1780000000"]

func queryItems(of request: URLRequest) -> [String: String] {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let items = components.queryItems else { return [:] }
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

func jsonBody(of request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}

// MARK: - Fixtures

let userJSON = """
{"login":"octocat","id":1,"name":"The Octocat","avatar_url":"https://github.com/images/octocat.png","html_url":"https://github.com/octocat"}
"""

let repoJSON = """
{"name":"Hello-World","full_name":"octocat/Hello-World","owner":{"login":"octocat"},"description":"My first repo","private":false,"html_url":"https://github.com/octocat/Hello-World","default_branch":"main","stargazers_count":42,"forks_count":7,"language":"Swift","created_at":"2024-01-15T10:30:00Z","updated_at":"2024-02-01T12:00:00Z","pushed_at":"2024-02-01T12:00:00Z"}
"""

let issueListJSON = """
[{"number":1,"title":"Found a bug","body":"Steps to reproduce","state":"open","user":{"login":"octocat"},"labels":[{"name":"bug"},{"name":"help wanted"}],"created_at":"2024-01-15T10:30:00Z","updated_at":"2024-01-16T10:30:00Z","html_url":"https://github.com/octocat/Hello-World/issues/1"},
 {"number":2,"title":"Fix the bug","body":null,"state":"open","user":{"login":"hubot"},"labels":[],"created_at":"2024-01-17T10:30:00Z","updated_at":"2024-01-17T10:30:00Z","html_url":"https://github.com/octocat/Hello-World/pull/2","pull_request":{"url":"https://api.github.com/repos/octocat/Hello-World/pulls/2"}}]
"""

let pullRequestJSON = """
{"number":2,"title":"Fix the bug","body":"This fixes it","state":"open","head":{"ref":"fix-bug","sha":"abc123"},"base":{"ref":"main","sha":"def456"},"user":{"login":"hubot"},"draft":false,"merged":false,"html_url":"https://github.com/octocat/Hello-World/pull/2","created_at":"2024-01-17T10:30:00Z","updated_at":"2024-01-18T10:30:00Z"}
"""

let treeJSON = """
{"sha":"mainsha","url":"https://api.github.com/repos/octocat/Hello-World/git/trees/main","tree":[{"path":"README.md","mode":"100644","type":"blob","sha":"aaa","size":42},{"path":"Sources","mode":"040000","type":"tree","sha":"bbb"}],"truncated":false}
"""

let searchIssuesJSON = """
{"total_count":1,"incomplete_results":false,"items":[{"number":1,"title":"Found a bug","body":"Steps","state":"open","user":{"login":"octocat"},"labels":[],"created_at":"2024-01-15T10:30:00Z","updated_at":"2024-01-16T10:30:00Z","html_url":"https://github.com/octocat/Hello-World/issues/1"}]}
"""

let searchCodeJSON = """
{"total_count":1,"incomplete_results":false,"items":[{"name":"main.swift","path":"Sources/main.swift","repository":{"full_name":"octocat/Hello-World"}}]}
"""

// The tests share the stub's static handler and recorded requests, so
// they run serialized.
@Suite("GitHubClient", .serialized)
struct GitHubClientTests {

    // MARK: - Request building

    @Test func repositoryRequestHasPathAndHeaders() async throws {
        let client = stubClient { _ in ok(repoJSON, headers: rateHeaders) }
        let repo = try await client.getRepository(owner: "octocat", repo: "Hello-World")
        #expect(repo.fullName == "octocat/Hello-World")
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url?.path == "/repos/octocat/Hello-World")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "SwiftCode")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test func unauthenticatedRequestOmitsAuthorization() async throws {
        let client = stubClient(token: nil) { _ in ok(userJSON) }
        _ = try await client.getRepository(owner: "octocat", repo: "Hello-World")
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    }

    @Test func emptyTokenOmitsAuthorization() async throws {
        let client = stubClient(token: "") { _ in ok(userJSON) }
        _ = try await client.getRepository(owner: "octocat", repo: "Hello-World")
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func perPageIsClampedTo1Through100() async throws {
        let client = stubClient { _ in ok("[]") }
        _ = try await client.listBranches(owner: "octocat", repo: "Hello-World", perPage: 500)
        #expect(queryItems(of: StubURLProtocol.requests[0])["per_page"] == "100")
        _ = try await client.listBranches(owner: "octocat", repo: "Hello-World", perPage: 0)
        #expect(queryItems(of: StubURLProtocol.requests[1])["per_page"] == "1")
    }

    @Test func listCommitsSendsBranchAndPerPage() async throws {
        let client = stubClient { _ in ok("[]") }
        _ = try await client.listCommits(owner: "octocat", repo: "Hello-World", branch: "feature/x", perPage: 5)
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url?.path == "/repos/octocat/Hello-World/commits")
        let query = queryItems(of: request)
        #expect(query["sha"] == "feature/x")
        #expect(query["per_page"] == "5")
    }

    @Test func getFileContentPercentEncodesThePath() async throws {
        let client = stubClient { _ in ok("{\"name\":\"c.txt\",\"path\":\"a b/c.txt\",\"sha\":\"aaa\",\"size\":5,\"content\":\"aGVsbG8=\",\"encoding\":\"base64\"}") }
        _ = try await client.getFileContent(owner: "octocat", repo: "Hello-World", path: "a b/c.txt", ref: "main")
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url?.path == "/repos/octocat/Hello-World/contents/a%20b/c.txt")
        #expect(queryItems(of: request)["ref"] == "main")
    }

    @Test func createIssueSendsPOSTWithJSONBody() async throws {
        let created = """
        {"number":3,"title":"New issue","body":"Details","state":"open","user":{"login":"octocat"},"labels":[{"name":"bug"}],"created_at":"2024-01-15T10:30:00Z","updated_at":"2024-01-15T10:30:00Z","html_url":"https://github.com/octocat/Hello-World/issues/3"}
        """
        let client = stubClient { _ in (201, [:], json(created)) }
        let issue = try await client.createIssue(owner: "octocat", repo: "Hello-World", title: "New issue", body: "Details", labels: ["bug"])
        #expect(issue.number == 3)
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = jsonBody(of: request)
        #expect(body["title"] as? String == "New issue")
        #expect(body["body"] as? String == "Details")
        #expect(body["labels"] as? [String] == ["bug"])
    }

    @Test func updateIssueSendsOnlyNonNilFields() async throws {
        let updated = """
        {"number":1,"title":"Renamed","body":"Steps","state":"open","user":{"login":"octocat"},"labels":[],"created_at":"2024-01-15T10:30:00Z","updated_at":"2024-01-16T10:30:00Z","html_url":"https://github.com/octocat/Hello-World/issues/1"}
        """
        let client = stubClient { _ in ok(updated) }
        _ = try await client.updateIssue(owner: "octocat", repo: "Hello-World", number: 1, title: "Renamed", body: nil, state: nil)
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.httpMethod == "PATCH")
        let body = jsonBody(of: request)
        #expect(body["title"] as? String == "Renamed")
        #expect(body["body"] == nil)
        #expect(body["state"] == nil)
    }

    @Test func searchIssuesSendsQuery() async throws {
        let client = stubClient { _ in ok(searchIssuesJSON) }
        let result = try await client.searchIssues(query: "repo:octocat/Hello-World bug", perPage: 10, page: 2)
        #expect(result.totalCount == 1)
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url?.path == "/search/issues")
        let query = queryItems(of: request)
        #expect(query["q"] == "repo:octocat/Hello-World bug")
        #expect(query["per_page"] == "10")
        #expect(query["page"] == "2")
    }

    @Test func createPullRequestSendsHeadBaseAndDraft() async throws {
        let client = stubClient { _ in (201, [:], json(pullRequestJSON)) }
        _ = try await client.createPullRequest(owner: "octocat", repo: "Hello-World", title: "Fix the bug", body: "This fixes it", head: "fix-bug", base: "main", draft: true)
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/repos/octocat/Hello-World/pulls")
        let body = jsonBody(of: request)
        #expect(body["head"] as? String == "fix-bug")
        #expect(body["base"] as? String == "main")
        #expect(body["draft"] as? Bool == true)
    }

    // MARK: - Response parsing

    @Test func userParses() async throws {
        let client = stubClient { _ in ok(userJSON) }
        let user = try await client.getAuthenticatedUser()
        #expect(user.login == "octocat")
        #expect(user.id == 1)
        #expect(user.name == "The Octocat")
        #expect(user.avatarUrl == "https://github.com/images/octocat.png")
        #expect(user.htmlUrl == "https://github.com/octocat")
    }

    @Test func repositoryParsesNestedOwnerAndPrivate() async throws {
        let client = stubClient { _ in ok(repoJSON) }
        let repo = try await client.getRepository(owner: "octocat", repo: "Hello-World")
        #expect(repo.name == "Hello-World")
        #expect(repo.ownerLogin == "octocat")
        #expect(repo.isPrivate == false)
        #expect(repo.defaultBranch == "main")
        #expect(repo.stargazersCount == 42)
        #expect(repo.forksCount == 7)
        #expect(repo.language == "Swift")
        #expect(repo.createdAt == Date(timeIntervalSince1970: 1705314600))
    }

    @Test func issueListParsesLabelsAndPullRequestFlag() async throws {
        let client = stubClient { _ in ok(issueListJSON) }
        let issues = try await client.listIssues(owner: "octocat", repo: "Hello-World")
        #expect(issues.count == 2)
        #expect(issues[0].labels == ["bug", "help wanted"])
        #expect(issues[0].isPullRequest == false)
        #expect(issues[1].isPullRequest == true)
        #expect(issues[1].userLogin == "hubot")
    }

    @Test func pullRequestParsesHeadAndBase() async throws {
        let client = stubClient { _ in ok(pullRequestJSON) }
        let pr = try await client.getPullRequest(owner: "octocat", repo: "Hello-World", number: 2)
        #expect(pr.headRef == "fix-bug")
        #expect(pr.headSha == "abc123")
        #expect(pr.baseRef == "main")
        #expect(pr.draft == false)
        #expect(pr.merged == false)
    }

    @Test func treeParsesEntries() async throws {
        let client = stubClient { _ in ok(treeJSON) }
        let tree = try await client.getRepoTree(owner: "octocat", repo: "Hello-World", ref: "main")
        #expect(tree.count == 2)
        #expect(tree[0].path == "README.md")
        #expect(tree[0].type == "blob")
        #expect(tree[0].size == 42)
        #expect(tree[1].size == nil)
        let request = try #require(StubURLProtocol.requests.first)
        #expect(queryItems(of: request)["recursive"] == "1")
    }

    @Test func searchCodeParsesRepositoryFullName() async throws {
        let client = stubClient { _ in ok(searchCodeJSON) }
        let result = try await client.searchCode(query: "main.swift")
        #expect(result.totalCount == 1)
        #expect(result.items[0].repositoryFullName == "octocat/Hello-World")
        #expect(result.items[0].path == "Sources/main.swift")
    }

    @Test func branchesCommitsReviewsAndFilesParse() async throws {
        let client = stubClient { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/branches") {
                return ok("[{\"name\":\"main\",\"commit\":{\"sha\":\"abc123\"}}]")
            }
            if path.hasSuffix("/commits") {
                return ok("[{\"sha\":\"abc123\",\"commit\":{\"message\":\"Initial commit\",\"author\":{\"name\":\"The Octocat\",\"date\":\"2024-01-15T10:30:00Z\"}}}]")
            }
            if path.hasSuffix("/reviews") {
                return ok("[{\"id\":1,\"user\":{\"login\":\"octocat\"},\"state\":\"APPROVED\",\"body\":\"LGTM\",\"submitted_at\":\"2024-01-18T10:30:00Z\"}]")
            }
            return ok("[{\"filename\":\"README.md\",\"status\":\"modified\",\"additions\":3,\"deletions\":1,\"changes\":4}]")
        }
        let branches = try await client.listBranches(owner: "octocat", repo: "Hello-World")
        #expect(branches.count == 1)
        #expect(branches[0].name == "main")
        #expect(branches[0].commitSha == "abc123")
        let commits = try await client.listCommits(owner: "octocat", repo: "Hello-World")
        #expect(commits[0].message == "Initial commit")
        #expect(commits[0].authorName == "The Octocat")
        let reviews = try await client.listPullRequestReviews(owner: "octocat", repo: "Hello-World", number: 2)
        #expect(reviews[0].state == "APPROVED")
        let files = try await client.listPullRequestFiles(owner: "octocat", repo: "Hello-World", number: 2)
        #expect(files[0].filename == "README.md")
        #expect(files[0].additions == 3)
    }

    @Test func fileTextDecodesWrappedBase64() async throws {
        // "hello world" base64, wrapped across lines the way the API returns it.
        let client = stubClient { _ in ok("{\"name\":\"c.txt\",\"path\":\"c.txt\",\"sha\":\"aaa\",\"size\":11,\"content\":\"aGVsbG8g\\nd29ybGQ=\\n\",\"encoding\":\"base64\"}") }
        let text = try await client.getFileText(owner: "octocat", repo: "Hello-World", path: "c.txt")
        #expect(text == "hello world")
    }

    @Test func fileTextRejectsInvalidBase64() async throws {
        let client = stubClient { _ in ok("{\"name\":\"c.txt\",\"path\":\"c.txt\",\"sha\":\"aaa\",\"size\":3,\"content\":\"!!!not-base64!!!\",\"encoding\":\"base64\"}") }
        await #expect(throws: GitHubError.decoding) {
            try await client.getFileText(owner: "octocat", repo: "Hello-World", path: "c.txt")
        }
    }

    @Test func rateLimitEndpointParsesReset() async throws {
        let client = stubClient { _ in ok("{\"resources\":{\"core\":{\"limit\":60,\"remaining\":59,\"reset\":1780000000}},\"rate\":{\"limit\":60,\"remaining\":59,\"reset\":1780000000}}") }
        let rate = try await client.rateLimit()
        #expect(rate.limit == 60)
        #expect(rate.remaining == 59)
        #expect(rate.resetAt == Date(timeIntervalSince1970: 1780000000))
    }

    // MARK: - Error mapping

    @Test func missingTokenWithoutARequest() async throws {
        let client = stubClient(token: nil) { _ in ok(userJSON) }
        await #expect(throws: GitHubError.missingToken) {
            try await client.getAuthenticatedUser()
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func status401MapsToUnauthorized() async throws {
        let client = stubClient { _ in error(401, message: "Bad credentials") }
        await #expect(throws: GitHubError.unauthorized) {
            try await client.getAuthenticatedUser()
        }
    }

    @Test func status404MapsToNotFound() async throws {
        let client = stubClient { _ in error(404, message: "Not Found") }
        await #expect(throws: GitHubError.notFound) {
            try await client.getRepository(owner: "octocat", repo: "Nope")
        }
    }

    @Test func status422MapsToUnprocessableWithMessage() async throws {
        let client = stubClient { _ in error(422, message: "Validation Failed") }
        await #expect(throws: GitHubError.unprocessable(message: "Validation Failed")) {
            try await client.createIssue(owner: "octocat", repo: "Hello-World", title: "", body: nil)
        }
    }

    @Test func status403WithExhaustedLimitMapsToRateLimited() async throws {
        let headers = ["X-RateLimit-Limit": "60", "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1780000000"]
        let client = stubClient { _ in error(403, message: "API rate limit exceeded", headers: headers) }
        await #expect(throws: GitHubError.forbidden(message: "API rate limit exceeded", rateLimited: true, resetAt: Date(timeIntervalSince1970: 1780000000))) {
            try await client.getRepository(owner: "octocat", repo: "Hello-World")
        }
        // The exhausted response still records the rate-limit state.
        #expect(client.lastRateLimit?.remaining == 0)
        #expect(client.lastRateLimit?.resetAt == Date(timeIntervalSince1970: 1780000000))
    }

    @Test func status403WithoutExhaustionMapsToForbidden() async throws {
        let client = stubClient { _ in error(403, message: "Resource not accessible by integration") }
        await #expect(throws: GitHubError.forbidden(message: "Resource not accessible by integration", rateLimited: false, resetAt: nil)) {
            try await client.getRepository(owner: "octocat", repo: "Hello-World")
        }
    }

    @Test func otherStatusesMapToHTTPWithMessage() async throws {
        let client = stubClient { _ in error(500, message: "Server Error") }
        await #expect(throws: GitHubError.http(status: 500, message: "Server Error")) {
            try await client.getRepository(owner: "octocat", repo: "Hello-World")
        }
    }

    @Test func invalidJSONMapsToDecoding() async throws {
        let client = stubClient { _ in ok("this is not json") }
        await #expect(throws: GitHubError.decoding) {
            try await client.getRepository(owner: "octocat", repo: "Hello-World")
        }
    }

    @Test func invalidRepoIsRejectedWithoutARequest() async throws {
        let client = stubClient { _ in ok(repoJSON) }
        await #expect(throws: GitHubError.invalidRepo("/")) {
            try await client.getRepository(owner: "", repo: "")
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    // MARK: - Rate-limit headers

    @Test func rateLimitHeadersAreRecordedAfterEveryResponse() async throws {
        let client = stubClient { _ in ok(repoJSON, headers: rateHeaders) }
        _ = try await client.getRepository(owner: "octocat", repo: "Hello-World")
        let recorded = try #require(client.lastRateLimit)
        #expect(recorded.limit == 60)
        #expect(recorded.remaining == 59)
        #expect(recorded.resetAt == Date(timeIntervalSince1970: 1780000000))
    }

    @Test func retryAfterHeaderIsRecorded() async throws {
        let headers = ["X-RateLimit-Limit": "60", "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1780000000", "Retry-After": "120"]
        let client = stubClient { _ in error(403, message: "API rate limit exceeded", headers: headers) }
        await #expect(throws: GitHubError.forbidden(message: "API rate limit exceeded", rateLimited: true, resetAt: Date(timeIntervalSince1970: 1780000000))) {
            try await client.getRepository(owner: "octocat", repo: "Hello-World")
        }
        #expect(client.lastRateLimit?.retryAfter == 120)
    }

    @Test func tokenProviderIsReadPerRequest() async throws {
        // A box, so the token can change between requests without
        // capturing a mutable local in a @Sendable closure.
        final class TokenBox: @unchecked Sendable {
            var current: String?
        }
        let box = TokenBox()
        box.current = "first-token"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in ok(userJSON) }
        StubURLProtocol.requests = []
        let client = GitHubClient(session: URLSession(configuration: config), tokenProvider: { box.current })
        _ = try await client.getAuthenticatedUser()
        box.current = "second-token"
        _ = try await client.getAuthenticatedUser()
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer first-token")
        #expect(StubURLProtocol.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer second-token")
    }
}
