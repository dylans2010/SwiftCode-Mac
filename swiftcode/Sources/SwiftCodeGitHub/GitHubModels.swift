import Foundation

/// The GitHub API rate-limit state: the headers on every response
/// (`X-RateLimit-Limit/Remaining/Reset`, `Retry-After`), and the `rate`
/// object of `GET /rate_limit` (where `reset` is a Unix timestamp).
public struct GitHubRateLimit: Sendable, Equatable, Decodable {
    public var limit: Int?
    public var remaining: Int?
    public var resetAt: Date?
    public var retryAfter: TimeInterval?

    public init(limit: Int? = nil, remaining: Int? = nil, resetAt: Date? = nil, retryAfter: TimeInterval? = nil) {
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
        self.retryAfter = retryAfter
    }

    public var isExhausted: Bool { remaining == 0 }

    /// Reads the rate-limit headers off a response. Missing headers stay nil.
    public static func parse(from response: HTTPURLResponse) -> GitHubRateLimit {
        func intHeader(_ name: String) -> Int? {
            response.value(forHTTPHeaderField: name).flatMap(Int.init)
        }
        let reset: Date? = intHeader("X-RateLimit-Reset").map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let retry: TimeInterval? = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
        return GitHubRateLimit(
            limit: intHeader("X-RateLimit-Limit"),
            remaining: intHeader("X-RateLimit-Remaining"),
            resetAt: reset,
            retryAfter: retry
        )
    }

    private enum CodingKeys: String, CodingKey {
        case limit, remaining, reset, retryAfter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        remaining = try container.decodeIfPresent(Int.self, forKey: .remaining)
        if let resetSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .reset) {
            resetAt = Date(timeIntervalSince1970: resetSeconds)
        } else {
            resetAt = nil
        }
        retryAfter = try container.decodeIfPresent(TimeInterval.self, forKey: .retryAfter)
    }
}

/// The authenticated user (`GET /user`).
public struct GitHubUser: Sendable, Equatable, Decodable {
    public var login: String
    public var id: Int
    public var name: String?
    public var avatarUrl: String?
    public var htmlUrl: String?
    // Profile fields (`GET /user` returns these; all optional so older
    // payloads still decode). Added for the GitHub account view.
    public var bio: String?
    public var company: String?
    public var blog: String?
    public var location: String?
    public var email: String?
    public var hireable: Bool?
    public var followers: Int?
    public var following: Int?
    public var publicRepos: Int?
    public var totalPrivateRepos: Int?
    public var createdAt: Date?
    public var updatedAt: Date?
}

/// A repository (`GET /repos/{owner}/{repo}`). `ownerLogin` is the nested
/// `owner.login`; `isPrivate` is the JSON `private` key.
public struct GitHubRepository: Sendable, Equatable, Decodable, Identifiable {
    /// Stable identity: the `owner/name` full name.
    public var id: String { fullName }
    public var name: String
    public var fullName: String
    public var ownerLogin: String
    public var description: String?
    public var isPrivate: Bool
    public var htmlUrl: String
    public var defaultBranch: String?
    public var stargazersCount: Int
    public var forksCount: Int
    public var language: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var pushedAt: Date?
    // Added for the public repository browser (topics, clone URLs) and
    // the repository dashboard (size in KB, open issue count).
    public var topics: [String]?
    public var sshUrl: String?
    public var cloneUrl: String?
    public var size: Int?
    public var openIssuesCount: Int?

    private enum CodingKeys: String, CodingKey {
        case name, fullName, description, htmlUrl, defaultBranch, stargazersCount, forksCount, language,
             createdAt, updatedAt, pushedAt, owner, topics, sshUrl, cloneUrl, size, openIssuesCount
        case isPrivate = "private"
    }

    private enum OwnerKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        fullName = try container.decode(String.self, forKey: .fullName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isPrivate = try container.decode(Bool.self, forKey: .isPrivate)
        htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        defaultBranch = try container.decodeIfPresent(String.self, forKey: .defaultBranch)
        stargazersCount = try container.decode(Int.self, forKey: .stargazersCount)
        forksCount = try container.decode(Int.self, forKey: .forksCount)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        pushedAt = try container.decodeIfPresent(Date.self, forKey: .pushedAt)
        topics = try container.decodeIfPresent([String].self, forKey: .topics)
        sshUrl = try container.decodeIfPresent(String.self, forKey: .sshUrl)
        cloneUrl = try container.decodeIfPresent(String.self, forKey: .cloneUrl)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        openIssuesCount = try container.decodeIfPresent(Int.self, forKey: .openIssuesCount)
        let owner = try container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner)
        ownerLogin = try owner.decode(String.self, forKey: .login)
    }
}

/// An issue (`/repos/{owner}/{repo}/issues`). `labels` are the label names;
/// `isPullRequest` is true when the `pull_request` key is present (issues
/// and pull requests share the issues endpoint).
public struct GitHubIssue: Sendable, Equatable, Decodable {
    public var number: Int
    public var title: String
    public var body: String?
    public var state: String
    public var userLogin: String
    public var labels: [String]
    public var createdAt: Date?
    public var updatedAt: Date?
    public var htmlUrl: String
    public var isPullRequest: Bool

    private enum CodingKeys: String, CodingKey {
        case number, title, body, state, labels, createdAt, updatedAt, htmlUrl, pullRequest, user
    }

    private struct Label: Decodable {
        var name: String
    }

    private enum UserKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        state = try container.decode(String.self, forKey: .state)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        labels = try container.decodeIfPresent([Label].self, forKey: .labels)?.map(\.name) ?? []
        let user = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        userLogin = try user.decode(String.self, forKey: .login)
        isPullRequest = container.contains(.pullRequest)
    }
}

/// A pull request (`/repos/{owner}/{repo}/pulls`). `headRef`/`headSha` are
/// the nested `head.ref`/`head.sha`; `baseRef` is `base.ref`.
public struct GitHubPullRequest: Sendable, Equatable, Decodable {
    public var number: Int
    public var title: String
    public var body: String?
    public var state: String
    public var headRef: String
    public var headSha: String?
    public var baseRef: String
    public var userLogin: String
    public var draft: Bool
    public var merged: Bool?
    public var htmlUrl: String
    public var createdAt: Date?
    public var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case number, title, body, state, head, base, user, draft, merged, htmlUrl, createdAt, updatedAt
    }

    private enum RefKeys: String, CodingKey {
        case ref, sha
    }

    private enum UserKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        state = try container.decode(String.self, forKey: .state)
        let head = try container.nestedContainer(keyedBy: RefKeys.self, forKey: .head)
        headRef = try head.decode(String.self, forKey: .ref)
        headSha = try head.decodeIfPresent(String.self, forKey: .sha)
        let base = try container.nestedContainer(keyedBy: RefKeys.self, forKey: .base)
        baseRef = try base.decode(String.self, forKey: .ref)
        let user = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        userLogin = try user.decode(String.self, forKey: .login)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        merged = try container.decodeIfPresent(Bool.self, forKey: .merged)
        htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// One file changed by a pull request (`/pulls/{number}/files`).
public struct GitHubPullRequestFile: Sendable, Equatable, Decodable {
    public var filename: String
    public var status: String
    public var additions: Int
    public var deletions: Int
    public var changes: Int
}

/// A pull-request review (`/pulls/{number}/reviews`).
public struct GitHubReview: Sendable, Equatable, Decodable, Identifiable {
    public var id: Int
    public var userLogin: String
    public var state: String
    public var body: String?
    public var submittedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, state, body, submittedAt, user
    }

    private enum UserKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        state = try container.decode(String.self, forKey: .state)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        submittedAt = try container.decodeIfPresent(Date.self, forKey: .submittedAt)
        let user = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        userLogin = try user.decode(String.self, forKey: .login)
    }
}

/// A branch (`/repos/{owner}/{repo}/branches`). `commitSha` is the nested
/// `commit.sha`.
public struct GitHubBranch: Sendable, Equatable, Decodable {
    public var name: String
    public var commitSha: String

    private enum CodingKeys: String, CodingKey {
        case name, commit
    }

    private enum CommitKeys: String, CodingKey {
        case sha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let commit = try container.nestedContainer(keyedBy: CommitKeys.self, forKey: .commit)
        commitSha = try commit.decode(String.self, forKey: .sha)
    }
}

/// A commit (`/repos/{owner}/{repo}/commits`). The message and author come
/// from the nested `commit` object (`commit.message`,
/// `commit.author.name`/`commit.author.date`).
public struct GitHubCommit: Sendable, Equatable, Decodable {
    public var sha: String
    public var message: String
    public var authorName: String?
    public var authorDate: Date?

    private enum CodingKeys: String, CodingKey {
        case sha, commit
    }

    private enum CommitKeys: String, CodingKey {
        case message, author
    }

    private enum AuthorKeys: String, CodingKey {
        case name, date
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try container.decode(String.self, forKey: .sha)
        let commit = try container.nestedContainer(keyedBy: CommitKeys.self, forKey: .commit)
        message = try commit.decode(String.self, forKey: .message)
        if let author = try? commit.nestedContainer(keyedBy: AuthorKeys.self, forKey: .author) {
            authorName = try author.decodeIfPresent(String.self, forKey: .name)
            authorDate = try author.decodeIfPresent(Date.self, forKey: .date)
        } else {
            authorName = nil
            authorDate = nil
        }
    }
}

/// One entry of a git tree (`/repos/{owner}/{repo}/git/trees/{ref}`).
public struct GitHubTreeEntry: Sendable, Equatable, Decodable {
    public var path: String
    public var type: String
    public var sha: String
    public var size: Int?
}

/// A file's content (`/repos/{owner}/{repo}/contents/{path}`). `content`
/// is base64 and may contain newlines; `getFileText` decodes it.
public struct GitHubFileContent: Sendable, Equatable, Decodable {
    public var name: String
    public var path: String
    public var sha: String
    public var size: Int
    public var content: String
    public var encoding: String
}

/// A search response (`/search/issues`, `/search/code`).
public struct GitHubSearchResult<T: Decodable & Sendable>: Sendable, Decodable {
    public var totalCount: Int
    public var items: [T]
}

/// One workflow run (`/repos/{owner}/{repo}/actions/runs`). Ported
/// from Legacy's `GitHubService.WorkflowRun`: `statusBadge` /
/// `isRunning` are the same derived values Legacy's views used.
public struct GitHubWorkflowRun: Sendable, Equatable, Decodable {
    public var id: Int
    public var name: String?
    public var status: String
    public var conclusion: String?
    public var htmlUrl: String
    public var createdAt: Date
    public var updatedAt: Date
    public var runNumber: Int
    public var headBranch: String?
    public var actor: GitHubUser?

    public var isRunning: Bool {
        status == "in_progress" || status == "queued"
    }

    public var statusBadge: String {
        switch conclusion ?? status {
        case "success": return "checkmark.circle.fill"
        case "failure": return "xmark.circle.fill"
        case "cancelled": return "slash.circle.fill"
        case "in_progress": return "clock.fill"
        default: return "circle"
        }
    }
}

/// One workflow (`GET /repos/{owner}/{repo}/actions/workflows`).
/// Ported from Legacy's `GitHubService.GitHubWorkflow` (the slice
/// that listed runs but never listed the workflows themselves).
public struct GitHubWorkflow: Sendable, Equatable, Decodable {
    public var id: Int
    public var name: String
    public var path: String
    public var state: String
    public var createdAt: Date
    public var updatedAt: Date
    public var htmlUrl: String
    public var badgeUrl: String

    /// `true` when GitHub will run this workflow (`state == "active"`).
    public var isActive: Bool { state == "active" }
}

/// A repository's GitHub Pages configuration
/// (`GET /repos/{owner}/{repo}/pages`). The `source` branch/path
/// pair only applies to legacy (branch-based) builds; workflow
/// builds report `buildType == "workflow"` and no source.
public struct GitHubPagesInfo: Sendable, Equatable, Decodable {
    public var url: String
    public var status: String?
    public var cname: String?
    public var custom404: Bool?
    public var htmlUrl: String?
    public var source: GitHubPagesSource?
    public var isPublic: Bool?
    public var httpsEnforced: Bool?
    public var buildType: String?

    private enum CodingKeys: String, CodingKey {
        case url, status, cname, source, htmlUrl, buildType
        case custom404 = "custom404"
        case isPublic = "public"
        case httpsEnforced = "httpsEnforced"
    }

    /// `true` when Pages serves this site over HTTPS only.
    public var isLive: Bool { status == "built" }
}

/// The branch/path pair a legacy Pages site builds from.
public struct GitHubPagesSource: Sendable, Equatable, Decodable {
    public var branch: String
    public var path: String
}

/// One Pages deployment (`GET /repos/{owner}/{repo}/pages/deployments`).
/// `latestStatus` carries the most recent build state; a deployment
/// that never built has no status.
public struct GitHubPagesDeployment: Sendable, Equatable, Decodable {
    public var id: Int
    public var statusUrl: String?
    public var environment: String?
    public var latestStatus: GitHubPagesDeploymentStatus?
    public var createdAt: Date
    public var updatedAt: Date
    public var description: String?
}

/// The latest build state of one Pages deployment.
public struct GitHubPagesDeploymentStatus: Sendable, Equatable, Decodable {
    public var id: Int
    public var status: String
    public var deploymentId: Int?
    public var environmentUrl: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var description: String?
}

/// One job of a workflow run
/// (`/repos/{owner}/{repo}/actions/runs/{run_id}/jobs`). Ported
/// from Legacy's `GitHubService.WorkflowJob`.
public struct GitHubWorkflowJob: Sendable, Equatable, Decodable {
    public var id: Int
    public var runId: Int
    public var status: String
    public var conclusion: String?
    public var startedAt: Date?
    public var completedAt: Date?
    public var name: String
    public var steps: [GitHubWorkflowStep]?

    public var isRunning: Bool {
        status == "in_progress" || status == "queued"
    }
}

/// One step of a workflow job. Ported from Legacy's
/// `GitHubService.GitHubWorkflowStep`.
public struct GitHubWorkflowStep: Sendable, Equatable, Decodable {
    public var name: String
    public var status: String
    public var conclusion: String?
    public var number: Int
}

/// One workflow artifact (`/actions/runs/{run_id}/artifacts`).
/// Ported from Legacy's `GitHubService.GitHubArtifact`.
public struct GitHubArtifact: Sendable, Equatable, Decodable {
    public var id: Int
    public var name: String
    public var sizeInBytes: Int
    public var archiveDownloadUrl: String?
    public var expired: Bool
}

// `GitHubRelease` / `GitHubReleaseAsset` are declared once, in
// GitHubReleases.swift (the Releases client's model). Legacy's
// `GitHubService.GitHubRelease` embedded `assets`; that field is carried on
// the single declaration there so both waves share one type.

/// One code-search hit. `repositoryFullName` is the nested
/// `repository.full_name`.
public struct GitHubCodeItem: Sendable, Equatable, Decodable {
    public var repositoryFullName: String
    public var path: String
    public var name: String

    private enum CodingKeys: String, CodingKey {
        case repository, path, name
    }

    private enum RepositoryKeys: String, CodingKey {
        case fullName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        let repository = try container.nestedContainer(keyedBy: RepositoryKeys.self, forKey: .repository)
        repositoryFullName = try repository.decode(String.self, forKey: .fullName)
    }
}
