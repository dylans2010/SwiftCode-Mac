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
}

/// A repository (`GET /repos/{owner}/{repo}`). `ownerLogin` is the nested
/// `owner.login`; `isPrivate` is the JSON `private` key.
public struct GitHubRepository: Sendable, Equatable, Decodable {
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

    private enum CodingKeys: String, CodingKey {
        case name, fullName, description, htmlUrl, defaultBranch, stargazersCount, forksCount, language,
             createdAt, updatedAt, pushedAt, owner
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
public struct GitHubReview: Sendable, Equatable, Decodable {
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
