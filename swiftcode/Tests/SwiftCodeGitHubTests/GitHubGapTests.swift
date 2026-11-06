import Foundation
import Testing
@testable import SwiftCodeGitHub

// Gap-closure tests: pushFile/getFileSHA, workflow runs/jobs/
// artifacts/logs, releases, repo ZIP, createRepository. Stub
// transport and fixtures only — no live network, no real token
// (the stub token is a placeholder).

// MARK: - Fixtures

let fileContentJSON = """
{"name":"README.md","path":"README.md","sha":"abc123sha","size":11,"content":"aGVsbG8gd29ybGQ=","encoding":"base64"}
"""

let workflowRunJSON = """
{"id":101,"name":"CI","status":"completed","conclusion":"success","html_url":"https://github.com/octocat/Hello-World/actions/runs/101","created_at":"2024-06-01T12:00:00Z","updated_at":"2024-06-01T12:05:00Z","run_number":7,"head_branch":"main","actor":{"login":"octocat","id":1,"name":"The Octocat","avatar_url":"https://github.com/images/octocat.png","html_url":"https://github.com/octocat"}}
"""

let workflowRunsJSON = """
{"total_count":1,"workflow_runs":[\(workflowRunJSON)]}
"""

let workflowJobsJSON = """
{"total_count":1,"jobs":[{"id":201,"run_id":101,"status":"completed","conclusion":"success","started_at":"2024-06-01T12:00:00Z","completed_at":"2024-06-01T12:04:00Z","name":"build","steps":[{"name":"Set up job","status":"completed","conclusion":"success","number":1},{"name":"Run tests","status":"completed","conclusion":"success","number":2}]}]}
"""

let artifactsJSON = """
{"total_count":1,"artifacts":[{"id":301,"name":"build-output","size_in_bytes":4096,"archive_download_url":"https://api.github.com/repos/octocat/Hello-World/actions/artifacts/301/zip","expired":false}]}
"""

let releasesJSON = """
[{"id":401,"tag_name":"v1.0.0","name":"First release","html_url":"https://github.com/octocat/Hello-World/releases/v1.0.0","created_at":"2024-05-01T10:00:00Z","assets":[{"id":501,"name":"app.zip","browser_download_url":"https://github.com/octocat/Hello-World/releases/download/v1.0.0/app.zip","size":8192}]}]
"""

struct GitHubGapTests {

    // MARK: - getFileSHA / pushFile

    @Test("getFileSHA returns the blob SHA for an existing file")
    func getFileSHAFound() async throws {
        let client = stubClient { _ in ok(fileContentJSON) }
        let sha = try await client.getFileSHA(owner: "octocat", repo: "Hello-World", path: "README.md")
        #expect(sha == "abc123sha")
        #expect(StubURLProtocol.requests[0].url?.path == "/repos/octocat/Hello-World/contents/README.md")
    }

    @Test("getFileSHA returns nil for a missing file (404), not an error")
    func getFileSHAMissing() async throws {
        let client = stubClient { _ in error(404, message: "Not Found") }
        #expect(try await client.getFileSHA(owner: "octocat", repo: "Hello-World", path: "MISSING.md") == nil)
    }

    @Test("getFileSHA throws on a non-404 failure instead of hiding it as missing")
    func getFileSHAAuthFailure() async {
        let client = stubClient { _ in error(401, message: "Bad credentials") }
        do {
            _ = try await client.getFileSHA(owner: "octocat", repo: "Hello-World", path: "README.md")
            Issue.record("Expected getFileSHA to throw")
        } catch let error as GitHubError {
            #expect(error == .unauthorized)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("pushFile creates a file: PUT with base64 content and no sha")
    func pushFileCreate() async throws {
        let client = stubClient { _ in ok("{\"content\":\(fileContentJSON),\"commit\":{\"sha\":\"def456\"}}") }
        let file = try await client.pushFile(
            owner: "octocat", repo: "Hello-World", path: "README.md",
            content: "hello world", message: "Add README")
        #expect(file.sha == "abc123sha")
        let request = StubURLProtocol.requests[0]
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/repos/octocat/Hello-World/contents/README.md")
        let body = jsonBody(of: request)
        #expect(body["message"] as? String == "Add README")
        #expect(body["content"] as? String == Data("hello world".utf8).base64EncodedString())
        #expect(body["sha"] == nil)
        #expect(body["branch"] == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test("pushFile updates a file: the current blob SHA is sent")
    func pushFileUpdate() async throws {
        let client = stubClient { _ in ok("{\"content\":\(fileContentJSON),\"commit\":{\"sha\":\"def456\"}}") }
        _ = try await client.pushFile(
            owner: "octocat", repo: "Hello-World", path: "README.md",
            content: "hello world v2", message: "Update README",
            sha: "abc123sha", branch: "feature")
        let body = jsonBody(of: StubURLProtocol.requests[0])
        #expect(body["sha"] as? String == "abc123sha")
        #expect(body["branch"] as? String == "feature")
    }

    @Test("pushFile surfaces a 422 validation error")
    func pushFileUnprocessable() async {
        let client = stubClient { _ in error(422, message: "Validation Failed") }
        do {
            _ = try await client.pushFile(
                owner: "octocat", repo: "Hello-World", path: "README.md",
                content: "x", message: "m")
            Issue.record("Expected pushFile to throw")
        } catch let error as GitHubError {
            #expect(error == .unprocessable(message: "Validation Failed"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Workflow runs, jobs, artifacts, logs

    @Test("listWorkflowRuns decodes runs with actor, status badge, and running state")
    func listWorkflowRuns() async throws {
        let client = stubClient { _ in ok(workflowRunsJSON) }
        let runs = try await client.listWorkflowRuns(owner: "octocat", repo: "Hello-World")
        #expect(runs.count == 1)
        #expect(runs[0].id == 101)
        #expect(runs[0].runNumber == 7)
        #expect(runs[0].headBranch == "main")
        #expect(runs[0].actor?.login == "octocat")
        #expect(runs[0].isRunning == false)
        #expect(runs[0].statusBadge == "checkmark.circle.fill")
        #expect(StubURLProtocol.requests[0].url?.path == "/repos/octocat/Hello-World/actions/runs")
    }

    @Test("getWorkflowRun decodes a single run")
    func getWorkflowRun() async throws {
        let client = stubClient { _ in ok(workflowRunJSON) }
        let run = try await client.getWorkflowRun(owner: "octocat", repo: "Hello-World", runID: 101)
        #expect(run.conclusion == "success")
        #expect(run.htmlUrl.contains("/actions/runs/101"))
    }

    @Test("listWorkflowJobs decodes jobs with steps")
    func listWorkflowJobs() async throws {
        let client = stubClient { _ in ok(workflowJobsJSON) }
        let jobs = try await client.listWorkflowJobs(owner: "octocat", repo: "Hello-World", runID: 101)
        #expect(jobs.count == 1)
        #expect(jobs[0].name == "build")
        #expect(jobs[0].runId == 101)
        #expect(jobs[0].steps?.count == 2)
        #expect(jobs[0].steps?[1].name == "Run tests")
        #expect(jobs[0].isRunning == false)
    }

    @Test("getJobLogs returns the log text")
    func getJobLogs() async throws {
        let client = stubClient { _ in ok("line one\nline two\n") }
        let logs = try await client.getJobLogs(owner: "octocat", repo: "Hello-World", jobID: 201)
        #expect(logs == "line one\nline two\n")
        #expect(StubURLProtocol.requests[0].url?.path == "/repos/octocat/Hello-World/actions/jobs/201/logs")
    }

    @Test("getWorkflowRunLogsURL returns the response URL")
    func getWorkflowRunLogsURL() async throws {
        // With a real URLSession GitHub answers the /logs endpoint
        // with a 302 to a short-lived download URL and the session
        // follows it, so the response URL is that download URL.
        // The stub transport does not follow redirects, so here the
        // returned URL is the request URL itself.
        let client = stubClient { _ in ok("") }
        let url = try await client.getWorkflowRunLogsURL(owner: "octocat", repo: "Hello-World", runID: 101)
        #expect(url.absoluteString == "https://api.github.com/repos/octocat/Hello-World/actions/runs/101/logs")
    }

    @Test("listWorkflowArtifacts decodes artifacts")
    func listWorkflowArtifacts() async throws {
        let client = stubClient { _ in ok(artifactsJSON) }
        let artifacts = try await client.listWorkflowArtifacts(owner: "octocat", repo: "Hello-World", runID: 101)
        #expect(artifacts.count == 1)
        #expect(artifacts[0].name == "build-output")
        #expect(artifacts[0].sizeInBytes == 4096)
        #expect(artifacts[0].expired == false)
    }

    @Test("downloadArtifact returns the ZIP bytes")
    func downloadArtifact() async throws {
        let client = stubClient { _ in (200, [:], Data([0x50, 0x4B, 0x03, 0x04])) }
        let data = try await client.downloadArtifact(owner: "octocat", repo: "Hello-World", artifactID: 301)
        #expect(data == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(StubURLProtocol.requests[0].url?.path == "/repos/octocat/Hello-World/actions/artifacts/301/zip")
    }

    // MARK: - Releases, repo ZIP, create repository

    @Test("listReleases decodes releases with assets")
    func listReleases() async throws {
        let client = stubClient { _ in ok(releasesJSON) }
        let releases = try await client.listReleases(owner: "octocat", repo: "Hello-World")
        #expect(releases.count == 1)
        #expect(releases[0].tagName == "v1.0.0")
        #expect(releases[0].name == "First release")
        #expect(releases[0].assets.count == 1)
        #expect(releases[0].assets[0].name == "app.zip")
        #expect(releases[0].assets[0].size == 8192)
    }

    @Test("downloadRepositoryZip returns the archive bytes for the requested branch")
    func downloadRepositoryZip() async throws {
        let client = stubClient { _ in (200, [:], Data("zip-bytes".utf8)) }
        let data = try await client.downloadRepositoryZip(owner: "octocat", repo: "Hello-World", branch: "develop")
        #expect(data == Data("zip-bytes".utf8))
        #expect(StubURLProtocol.requests[0].url?.path == "/repos/octocat/Hello-World/zipball/develop")
    }

    @Test("createRepository posts to user/repos and returns the created repo")
    func createRepository() async throws {
        let client = stubClient { _ in ok(repoJSON) }
        let repo = try await client.createRepository(name: "Hello-World", description: "My first repo", isPrivate: false)
        #expect(repo.fullName == "octocat/Hello-World")
        #expect(repo.isPrivate == false)
        let request = StubURLProtocol.requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/user/repos")
        let body = jsonBody(of: request)
        #expect(body["name"] as? String == "Hello-World")
        #expect(body["description"] as? String == "My first repo")
        #expect(body["private"] as? Bool == false)
        #expect(body["auto_init"] as? Bool == false)
    }

    @Test("createRepository without a token throws missingToken before any network call")
    func createRepositoryWithoutToken() async {
        let client = stubClient(token: nil) { _ in ok(repoJSON) }
        do {
            _ = try await client.createRepository(name: "x", description: "", isPrivate: false)
            Issue.record("Expected createRepository to throw")
        } catch let error as GitHubError {
            #expect(error == .missingToken)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }
}
