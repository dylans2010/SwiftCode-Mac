import Foundation
import Testing
@testable import YcodeGitHub

// Fixtures are synthetic: made-up gists, releases, notifications and
// comments. No real token is used anywhere; the stub token is a
// placeholder. The `StubURLProtocol` / `json` / `ok` helpers live in
// `GitHubClientTests.swift` in this same target.

private func stubSession(
    handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)
) -> URLSession {
    StubURLProtocol.requests = []
    StubURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private let gistJSON = """
{
  "id": "abc123",
  "description": "Hello gist",
  "public": true,
  "owner": {"login": "octo", "id": 1},
  "files": {
    "hello.txt": {"filename": "hello.txt", "type": "text/plain", "language": "Text", "raw_url": "https://example.com/raw", "size": 2, "content": "hi"}
  },
  "comments": 2,
  "created_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-01-02T00:00:00Z",
  "html_url": "https://gist.github.com/abc123",
  "history": [
    {"version": "deadbeef", "user": {"login": "octo", "id": 1}, "committed_at": "2026-01-01T00:00:00Z", "change_status": {"additions": 1, "deletions": 0, "total": 1}}
  ]
}
"""

@Suite struct GitHubExtendedClientsTests {
    @Test func gistListDecodesFilesAndHistory() async throws {
        let session = stubSession { _ in ok("[\(gistJSON)]") }
        let client = GitHubGistClient(session: session, tokenProvider: { "test-token" })
        let gists = try await client.listGists()
        #expect(gists.count == 1)
        let gist = gists[0]
        #expect(gist.id == "abc123")
        #expect(gist.description == "Hello gist")
        #expect(gist.isPublic)
        #expect(gist.owner?.login == "octo")
        #expect(gist.sortedFiles.map(\.filename) == ["hello.txt"])
        #expect(gist.sortedFiles.first?.content == "hi")
        #expect(gist.history.count == 1)
        #expect(gist.history[0].version == "deadbeef")
        #expect(gist.history[0].changeStatus?.additions == 1)
    }

    @Test func gistListWithoutTokenFailsHonestly() async {
        let session = stubSession { _ in ok("[]") }
        let client = GitHubGistClient(session: session, tokenProvider: { nil })
        await #expect(throws: GitHubError.missingToken) {
            try await client.listGists()
        }
    }

    @Test func gistCreatePostsFiles() async throws {
        let session = stubSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/gists")
            return ok(gistJSON)
        }
        let client = GitHubGistClient(session: session, tokenProvider: { "test-token" })
        let gist = try await client.createGist(description: "Hello gist", isPublic: true, files: ["hello.txt": "hi"])
        #expect(gist.id == "abc123")
    }

    @Test func gistStarCheckMaps404ToFalse() async throws {
        let session = stubSession { _ in error(404, message: "Not Found") }
        let client = GitHubGistClient(session: session, tokenProvider: { "test-token" })
        #expect(try await client.isStarred(id: "abc123") == false)
    }

    @Test func gistRevisionFetchUsesShaPath() async throws {
        let session = stubSession { request in
            #expect(request.url?.path == "/gists/abc123/deadbeef")
            return ok(gistJSON)
        }
        let client = GitHubGistClient(session: session, tokenProvider: { "test-token" })
        let gist = try await client.fetchGistAtRevision(id: "abc123", sha: "deadbeef")
        #expect(gist.id == "abc123")
    }

    @Test func releaseListDecodes() async throws {
        let body = """
        [{"id": 7, "tag_name": "v1.2.3", "name": "Release 1.2.3", "body": "Notes", "draft": false, "prerelease": false,
          "author": {"login": "octo", "id": 1}, "created_at": "2026-01-01T00:00:00Z", "published_at": "2026-01-02T00:00:00Z",
          "html_url": "https://github.com/o/r/releases/v1.2.3"}]
        """
        let session = stubSession { request in
            #expect(request.url?.path == "/repos/o/r/releases")
            return ok(body)
        }
        let client = GitHubReleaseClient(session: session, tokenProvider: { "test-token" })
        let releases = try await client.listReleases(owner: "o", repo: "r")
        #expect(releases.count == 1)
        #expect(releases[0].tagName == "v1.2.3")
        #expect(releases[0].authorLogin == "octo")
    }

    @Test func notificationListDecodesAndMarkReadPatches() async throws {
        let body = """
        [{"id": "99", "unread": true, "reason": "mention",
          "subject": {"title": "Fix the bug", "type": "Issue", "url": "https://api.github.com/repos/o/r/issues/1"},
          "repository": {"full_name": "o/r"}, "updated_at": "2026-01-02T00:00:00Z"}]
        """
        let session = stubSession { request in
            if request.httpMethod == "PATCH" {
                #expect(request.url?.path == "/notifications/threads/99")
                return (204, [:], Data())
            }
            return ok(body)
        }
        let client = GitHubRemoteListsClient(session: session, tokenProvider: { "test-token" })
        let notifications = try await client.listNotifications()
        #expect(notifications.count == 1)
        #expect(notifications[0].subjectTitle == "Fix the bug")
        #expect(notifications[0].repositoryFullName == "o/r")
        try await client.markNotificationRead(threadId: "99")
    }

    @Test func organizationAndUserRepoListsDecode() async throws {
        let session = stubSession { request in
            if request.url?.path == "/user/orgs" {
                return ok("[{\"id\": 5, \"login\": \"acme\", \"description\": \"Acme Corp\"}]")
            }
            return ok("[{\"name\": \"r\", \"full_name\": \"o/r\", \"owner\": {\"login\": \"o\"}, \"private\": false, \"html_url\": \"https://github.com/o/r\", \"stargazers_count\": 3, \"forks_count\": 1}]")
        }
        let client = GitHubRemoteListsClient(session: session, tokenProvider: { "test-token" })
        let orgs = try await client.listOrganizations()
        #expect(orgs.map(\.login) == ["acme"])
        let repos = try await client.listUserRepositories()
        #expect(repos.map(\.fullName) == ["o/r"])
    }

    @Test func issueCommentRoundTrip() async throws {
        let body = """
        {"id": 11, "body": "Looks good", "user": {"login": "octo"}, "created_at": "2026-01-02T00:00:00Z",
         "updated_at": "2026-01-02T00:00:00Z", "html_url": "https://github.com/o/r/issues/1#issuecomment-11"}
        """
        let session = stubSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/repos/o/r/issues/1/comments")
            return ok(body)
        }
        let client = GitHubIssueCommentClient(session: session, tokenProvider: { "test-token" })
        let comment = try await client.createIssueComment(owner: "o", repo: "r", number: 1, body: "Looks good")
        #expect(comment.id == 11)
        #expect(comment.userLogin == "octo")
    }

    @Test func unknownRepoReturnsNotFound() async {
        let session = stubSession { _ in error(404, message: "Not Found") }
        let client = GitHubReleaseClient(session: session, tokenProvider: { "test-token" })
        await #expect(throws: GitHubError.notFound) {
            try await client.listReleases(owner: "o", repo: "nope")
        }
    }
}
