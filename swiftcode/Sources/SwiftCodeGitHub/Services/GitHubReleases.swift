import Foundation

/// A release (`GET /repos/{owner}/{repo}/releases`). `authorLogin`
/// is the nested `author.login`.
public struct GitHubRelease: Sendable, Equatable, Decodable, Identifiable {
    public var id: Int
    public var tagName: String
    public var name: String?
    public var body: String?
    public var draft: Bool
    public var prerelease: Bool
    public var authorLogin: String?
    public var createdAt: Date?
    public var publishedAt: Date?
    public var htmlUrl: String?
    /// Assets embedded in the release payload (Legacy's
    /// `GitHubService.GitHubRelease.assets`). Empty when the payload
    /// omits them; the Releases view reads them from
    /// `GitHubReleaseClient.listReleaseAssets` when it needs the full list.
    public var assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case id, tagName, name, body, draft, prerelease, author, createdAt, publishedAt, htmlUrl, assets
    }

    private enum AuthorKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        htmlUrl = try container.decodeIfPresent(String.self, forKey: .htmlUrl)
        assets = (try? container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets)) ?? []
        if let author = try? container.nestedContainer(keyedBy: AuthorKeys.self, forKey: .author) {
            authorLogin = try author.decodeIfPresent(String.self, forKey: .login)
        } else {
            authorLogin = nil
        }
    }
}

/// One asset of a release (`/releases/{id}/assets`).
/// `downloadCount` is the JSON `download_count`.
public struct GitHubReleaseAsset: Sendable, Equatable, Decodable, Identifiable {
    public var id: Int
    public var name: String
    public var label: String?
    public var size: Int
    public var downloadCount: Int
    public var browserDownloadUrl: String?
    public var contentType: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        downloadCount = try container.decodeIfPresent(Int.self, forKey: .downloadCount) ?? 0
        browserDownloadUrl = try container.decodeIfPresent(String.self, forKey: .browserDownloadUrl)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, label, size, downloadCount, browserDownloadUrl, contentType
    }
}

/// The api.github.com releases client. There is no releases surface
/// in `GitHubClient` (Wave 10), so this is the port of Legacy's
/// `ReleasesView` data layer (`SwiftCode/Views/GitHub/ReleasesView.swift`):
/// list and read releases and their assets over
/// `GitHubRESTTransport`. Releases are read-only here — creating one
/// is a release-management action with no Legacy equivalent in this
/// slice, and stays out on purpose.
public struct GitHubReleaseClient: Sendable {
    private let transport: GitHubRESTTransport

    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { nil }) {
        self.transport = GitHubRESTTransport(session: session, tokenProvider: tokenProvider)
    }

    /// `GET /repos/{owner}/{repo}/releases`.
    public func listReleases(owner: String, repo: String, perPage: Int = 30, page: Int = 1) async throws -> [GitHubRelease] {
        try validateRepo(owner: owner, repo: repo)
        return try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/releases",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))"),
                    URLQueryItem(name: "page", value: "\(max(1, page))")]))
    }

    /// `GET /repos/{owner}/{repo}/releases/{id}`.
    public func getRelease(owner: String, repo: String, id: Int) async throws -> GitHubRelease {
        try validateRepo(owner: owner, repo: repo)
        return try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/releases/\(id)"))
    }

    /// `GET /repos/{owner}/{repo}/releases/latest`.
    public func getLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        try validateRepo(owner: owner, repo: repo)
        return try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/releases/latest"))
    }

    /// `GET /repos/{owner}/{repo}/releases/{id}/assets`.
    public func listReleaseAssets(owner: String, repo: String, releaseId: Int, perPage: Int = 30) async throws -> [GitHubReleaseAsset] {
        try validateRepo(owner: owner, repo: repo)
        return try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/releases/\(releaseId)/assets",
            query: [URLQueryItem(name: "per_page", value: "\(transport.clampedPerPage(perPage))")]))
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
