// Ported from Legacy `SwiftCode/Backend/Git/GitHubService.swift` (Audit E §5 partial entry; H-E5).
// (H-GH note, batch 9: the six Legacy-internal model types formerly declared here
//  NoRedirectDelegate, GitHubRepo, WorkflowRun, GitHubAsset, GitHubTreeResponse,
//  WorkflowJob - were deleted as unused; the public service uses GitHubClient's
//  production models. GitHubTreeEntry lives in GitHubModels.swift.)
// GitHubService itself (H-GH): the public service class below, delegating REST to GitHubClient
// and implementing fetchRepositories / fetchDiscussions / createBranchRef / pushProject /
// pushFileData / initializeGitHubRepository on GitHubRESTTransport. DiscussionThread /
// DiscussionReply live in GitHubServiceModels.swift.

import Foundation


// MARK: - GitHubService

/// The api.github.com service behind the Source Control / CI views
/// (`WorkflowRunsView`, `BuildLogsView`, `GitHubIntelligenceAndOperations`,
/// `DiscussionsView`, `CommitHistoryView`, `DeploymentTargets`,
/// `ProjectTemplateView`).
///
/// Ported from Legacy `SwiftCode/Backend/Git/GitHubService.swift` (Audit A
/// PARTIAL). The REST surface is delegated to the production
/// `GitHubClient` — same endpoints, same production models
/// (`GitHubWorkflowRun`, `GitHubWorkflowJob`, `GitHubArtifact`,
/// `GitHubPullRequest`, `GitHubRelease`, `GitHubCommit`, `GitHubBranch`,
/// `GitHubRepository`) — so the service and the client cannot drift apart.
/// Only the pieces `GitHubClient` does not have live here: the
/// `GET /user/repos` list (`fetchRepositories`), the GraphQL discussions
/// query (`fetchDiscussions`), the git-ref write (`createBranchRef`), the
/// Git Data API project push (`pushProject`), the contents-API binary push
/// (`pushFileData`), and the template initialiser
/// (`initializeGitHubRepository`), all implemented on the shared
/// `GitHubRESTTransport` below.
///
/// The token is never stored here. `shared` starts with no token (public
/// reads work; authenticated calls throw `.missingToken`, as in Legacy).
/// The app wires the saved token once at startup:
/// `GitHubService.shared.configure(tokenProvider: { <secret store>.readString(...) })`.
/// `fetchRepositories(token:)` takes its token per call, as in Legacy.
public final class GitHubService: @unchecked Sendable {
    public static let shared = GitHubService()

    private let session: URLSession
    private let tokenBox = TokenBox()

    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { nil }) {
        self.session = session
        tokenBox.set(tokenProvider)
    }

    /// Points the shared service at the user's saved GitHub token.
    public func configure(tokenProvider: @escaping @Sendable () -> String?) {
        tokenBox.set(tokenProvider)
    }

    private func client() -> GitHubClient {
        GitHubClient(session: session, tokenProvider: { [tokenBox] in tokenBox.get() })
    }

    private func transport() -> GitHubRESTTransport {
        GitHubRESTTransport(session: session, tokenProvider: { [tokenBox] in tokenBox.get() })
    }

    private func requireToken() throws {
        guard let token = tokenBox.get(), !token.isEmpty else { throw GitHubError.missingToken }
    }

    // MARK: - Repositories

    /// `GET /user/repos?sort=updated&per_page=100` with the given token.
    /// Legacy authenticated this call as `token <token>`; the transport
    /// sends the same token as `Bearer <token>`, which GitHub accepts
    /// identically.
    public func fetchRepositories(token: String) async throws -> [GitHubRepository] {
        guard !token.isEmpty else { throw GitHubError.missingToken }
        let transport = GitHubRESTTransport(session: session, tokenProvider: { token })
        let request = transport.request(path: "user/repos", query: [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "100"),
        ])
        return try await transport.perform(request)
    }

    /// `GET /repos/{owner}/{repo}` + branch list: empty when the repo has
    /// size 0 or no branches (Legacy's rule, via `GitHubRepository.size`).
    public func isRepositoryEmpty(owner: String, repo: String) async throws -> Bool {
        let detail = try await client().getRepository(owner: owner, repo: repo)
        if (detail.size ?? 0) == 0 { return true }
        return try await client().listBranches(owner: owner, repo: repo).isEmpty
    }

    // MARK: - Repository metadata (GitHubRepositoryManager backing)

    /// Thin authenticated passthroughs over `GitHubClient`, added so
    /// `GitHubRepositoryManager` (the port of Legacy's manager, whose
    /// `GitHubAPIBackend` was never ported) can be backed by the shared
    /// service's token instead of constructing an unauthenticated client.

    /// `GET /repos/{owner}/{repo}` (Legacy's `GitHubAPIBackend.getRepository`).
    public func getRepository(owner: String, repo: String) async throws -> GitHubRepository {
        try requireToken()
        return try await client().getRepository(owner: owner, repo: repo)
    }

    /// `GET /repos/{owner}/{repo}/branches` (Legacy's `GitHubAPIBackend.listBranches`).
    public func listBranches(owner: String, repo: String) async throws -> [GitHubBranch] {
        try requireToken()
        return try await client().listBranches(owner: owner, repo: repo)
    }

    /// `POST /user/repos` (Legacy's `GitHubAPIBackend.createRepository`).
    /// Returns `GitHubRepository`, the production equivalent of Legacy's
    /// five-field `GitHubRepo`.
    public func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepository {
        try requireToken()
        return try await client().createRepository(name: name, description: description, isPrivate: isPrivate)
    }

    /// `GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1`
    /// (Legacy's `GitHubAPIBackend.getRepoTree`).
    public func getRepoTree(owner: String, repo: String, branch: String = "main") async throws -> [GitHubTreeEntry] {
        try requireToken()
        return try await client().getRepoTree(owner: owner, repo: repo, ref: branch)
    }

    /// `GET /repos/{owner}/{repo}/contents/{path}` as decoded text
    /// (Legacy's `GitHubAPIBackend.getFileContent`, which returned `String`).
    public func getFileText(owner: String, repo: String, path: String, ref: String? = nil) async throws -> String {
        try requireToken()
        return try await client().getFileText(owner: owner, repo: repo, path: path, ref: ref)
    }

    /// Creates the `README.md` initial commit (Legacy's
    /// `initializeRepository`).
    public func initializeRepository(owner: String, repo: String, branch: String = "main") async throws {
        try await pushFile(
            owner: owner,
            repo: repo,
            path: "README.md",
            content: "# \(repo)\n\nCreated by SwiftCode.",
            message: "Initial commit created by SwiftCode",
            branch: branch
        )
    }

    /// Creates a repository for the template at `directoryURL`, pushes its
    /// `README.md`, then uploads every other regular file under it
    /// (skipping `project.json`). Legacy's `initializeGitHubRepository(for:)`
    /// took a `Project`; `SwiftCodeGitHub` cannot depend on the project
    /// model, so the caller passes the parsed `owner`/`repo` and the
    /// project directory instead. A 422 from repository creation (the repo
    /// already exists) is treated as success, as in Legacy; other creation
    /// failures are logged and the upload continues.
    public func initializeGitHubRepository(
        owner: String,
        repo: String,
        projectName: String,
        projectDescription: String,
        directoryURL: URL,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws {
        // Step 1: Detect and scan
        logHandler("Scanning template files")
        var filesToUpload: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues?.isRegularFile == true, fileURL.lastPathComponent != "project.json" {
                filesToUpload.append(fileURL)
            }
        }

        // Step 2: Create the GitHub repository
        logHandler("Creating GitHub repository")
        do {
            _ = try await client().createRepository(name: repo, description: projectDescription, isPrivate: false)
            logHandler("Repository created successfully")
        } catch {
            if let githubError = error as? GitHubError, case .unprocessable = githubError {
                logHandler("Repository created successfully")
            } else {
                logHandler("Repository creation: \(error.localizedDescription)")
            }
        }

        // Step 3: Create initial commit
        logHandler("Creating initial commit")
        let readmeURL = directoryURL.appendingPathComponent("README.md")
        let readmeContent: String
        if FileManager.default.fileExists(atPath: readmeURL.path) {
            readmeContent = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? "# \(projectName)\n\nCreated with SwiftCode."
        } else {
            readmeContent = "# \(projectName)\n\nCreated with SwiftCode."
        }

        let existingReadmeSHA = try? await getFileSHA(owner: owner, repo: repo, path: "README.md", branch: "main")
        try await pushFile(
            owner: owner,
            repo: repo,
            path: "README.md",
            content: readmeContent,
            message: "Initial commit created by SwiftCode",
            sha: existingReadmeSHA,
            branch: "main"
        )

        // Step 4: Upload full template codebase
        logHandler("Uploading template files to GitHub")
        for fileURL in filesToUpload {
            let relativePath = String(fileURL.path.dropFirst(directoryURL.path.count + 1))
            if relativePath == "README.md" { continue }

            let data = try Data(contentsOf: fileURL)
            let existingSHA = try? await getFileSHA(owner: owner, repo: repo, path: relativePath, branch: "main")
            try await pushFileData(
                owner: owner,
                repo: repo,
                path: relativePath,
                data: data,
                message: "Add template file: \(fileURL.lastPathComponent)",
                sha: existingSHA,
                branch: "main"
            )
        }

        logHandler("Repository initialized successfully")
    }

    // MARK: - Commits, branches, trees

    /// `GET /repos/{owner}/{repo}/commits` (Legacy defaults: `main`, 10).
    public func listCommits(owner: String, repo: String, branch: String = "main", perPage: Int = 10) async throws -> [GitHubCommit] {
        try requireToken()
        return try await client().listCommits(owner: owner, repo: repo, branch: branch, perPage: perPage)
    }

    // MARK: - Commit detail (GitHubCommitDetailView backing)

    /// `GET /repos/{owner}/{repo}/commits/{sha}` — the commit's changed
    /// files with their patches, for the diff preview (Legacy's
    /// `GitHubService.fetchCommitDetail`).
    public func fetchCommitDetail(owner: String, repo: String, sha: String) async throws -> GitHubCommitDetailResponse {
        try requireToken()
        let transport = transport()
        let request = transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/commits/\(transport.encode(sha))"
        )
        return try await transport.perform(request)
    }

    /// The named branch, or `nil` when it does not exist (Legacy's
    /// `getBranch`, via the branch list).
    public func getBranch(owner: String, repo: String, branch: String) async throws -> GitHubBranch? {
        try requireToken()
        return try await client().listBranches(owner: owner, repo: repo).first { $0.name == branch }
    }

    /// `POST /repos/{owner}/{repo}/git/refs` — creates `refs/heads/<branch>`
    /// at `sha` (Legacy's `createBranchRef`).
    public func createBranchRef(owner: String, repo: String, branch: String, sha: String) async throws {
        try requireToken()
        let transport = transport()
        let body = try JSONSerialization.data(withJSONObject: [
            "ref": "refs/heads/\(branch)",
            "sha": sha,
        ])
        let request = transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/git/refs",
            method: "POST",
            body: body
        )
        try await transport.performVoid(request)
    }

    /// Pushes a whole project snapshot through the Git Data API
    /// (blobs → tree → commit → ref update), exactly as Legacy's
    /// `pushProject`. Legacy took a `Project`; this takes the collected
    /// `(path, data)` pairs so the caller — which owns the project model —
    /// does the file walk.
    public func pushProject(
        owner: String,
        repo: String,
        branch: String = "main",
        commitMessage: String,
        files: [(path: String, data: Data)]
    ) async throws {
        try requireToken()
        let transport = transport()

        // 1. Get the latest commit SHA of the branch
        let branchRef = try await getBranchRef(owner: owner, repo: repo, branch: branch, transport: transport)
        let baseTreeSHA = try await getCommitTreeSHA(owner: owner, repo: repo, commitSHA: branchRef.object.sha, transport: transport)

        // 2. Create blobs for each file
        var treeEntries: [[String: Any]] = []
        for file in files {
            let blobSHA = try await createBlob(owner: owner, repo: repo, data: file.data, transport: transport)
            treeEntries.append([
                "path": file.path,
                "mode": "100644",
                "type": "blob",
                "sha": blobSHA,
            ])
        }

        // 3. Create a new tree
        let newTreeSHA = try await createTree(owner: owner, repo: repo, baseTreeSHA: baseTreeSHA, entries: treeEntries, transport: transport)

        // 4. Create a new commit
        let newCommitSHA = try await createCommit(owner: owner, repo: repo, message: commitMessage, treeSHA: newTreeSHA, parentSHA: branchRef.object.sha, transport: transport)

        // 5. Update the branch reference
        try await updateBranchRef(owner: owner, repo: repo, branch: branch, commitSHA: newCommitSHA, transport: transport)
    }

    // MARK: - Files

    /// `GET /repos/{owner}/{repo}/contents/{path}` → the file's blob SHA,
    /// or `nil` when the file does not exist (Legacy's `getFileSHA`).
    public func getFileSHA(owner: String, repo: String, path: String, branch: String? = nil) async throws -> String? {
        try requireToken()
        return try await client().getFileSHA(owner: owner, repo: repo, path: path, ref: branch)
    }

    /// `PUT /repos/{owner}/{repo}/contents/{path}` — create or update a
    /// file from text (Legacy's `pushFile`).
    public func pushFile(
        owner: String,
        repo: String,
        path: String,
        content: String,
        message: String,
        sha: String? = nil,
        branch: String? = nil
    ) async throws {
        try requireToken()
        _ = try await client().pushFile(owner: owner, repo: repo, path: path, content: content, message: message, sha: sha, branch: branch)
    }

    /// `PUT /repos/{owner}/{repo}/contents/{path}` — create or update a
    /// file from raw bytes (Legacy's `pushFileData`; the client only takes
    /// text, so binary template files need this).
    public func pushFileData(
        owner: String,
        repo: String,
        path: String,
        data: Data,
        message: String,
        sha: String? = nil,
        branch: String? = nil
    ) async throws {
        try requireToken()
        let transport = transport()
        var body: [String: Any] = [
            "message": message,
            "content": data.base64EncodedString(),
        ]
        if let sha { body["sha"] = sha }
        if let branch { body["branch"] = branch }
        let request = transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/contents/\(transport.encode(path))",
            method: "PUT",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        try await transport.performVoid(request)
    }

    // MARK: - Workflow runs, jobs, artifacts

    /// `GET /repos/{owner}/{repo}/actions/runs`.
    public func listWorkflowRuns(owner: String, repo: String) async throws -> [GitHubWorkflowRun] {
        try requireToken()
        return try await client().listWorkflowRuns(owner: owner, repo: repo)
    }

    /// `GET /repos/{owner}/{repo}/actions/runs/{runID}/jobs`.
    public func listWorkflowJobs(owner: String, repo: String, runID: Int) async throws -> [GitHubWorkflowJob] {
        try requireToken()
        return try await client().listWorkflowJobs(owner: owner, repo: repo, runID: runID)
    }

    /// `GET /repos/{owner}/{repo}/actions/jobs/{jobID}/logs`, with ANSI
    /// escape codes stripped (Legacy's `getJobLogs` + `sanitizeWorkflowLogs`).
    public func getJobLogs(owner: String, repo: String, jobID: Int) async throws -> String {
        try requireToken()
        return sanitizeWorkflowLogs(try await client().getJobLogs(owner: owner, repo: repo, jobID: jobID))
    }

    /// `GET /repos/{owner}/{repo}/actions/runs/{runID}/artifacts`.
    public func listWorkflowArtifacts(owner: String, repo: String, runID: Int) async throws -> [GitHubArtifact] {
        try requireToken()
        return try await client().listWorkflowArtifacts(owner: owner, repo: repo, runID: runID)
    }

    /// `GET /repos/{owner}/{repo}/actions/artifacts/{artifactID}/zip`.
    public func downloadArtifact(owner: String, repo: String, artifactID: Int) async throws -> Data {
        try requireToken()
        return try await client().downloadArtifact(owner: owner, repo: repo, artifactID: artifactID)
    }

    // MARK: - Pull requests, releases

    /// `GET /repos/{owner}/{repo}/pulls`.
    public func listPullRequests(owner: String, repo: String) async throws -> [GitHubPullRequest] {
        try requireToken()
        return try await client().listPullRequests(owner: owner, repo: repo)
    }

    /// `GET /repos/{owner}/{repo}/releases`.
    public func listReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
        try requireToken()
        return try await client().listReleases(owner: owner, repo: repo)
    }

    // MARK: - Discussions (GraphQL)

    /// `POST https://api.github.com/graphql` — the first 20 discussions
    /// of the repo with their first 10 comments each, mapped to
    /// `DiscussionThread` / `DiscussionReply` (Legacy's `fetchDiscussions`).
    public func fetchDiscussions(owner: String, repo: String) async throws -> [DiscussionThread] {
        guard let token = tokenBox.get(), !token.isEmpty else {
            throw GitHubError.missingToken
        }

        let query = """
        query($owner: String!, $repo: String!) {
          repository(owner: $owner, name: $repo) {
            discussions(first: 20) {
              nodes {
                id
                title
                body
                createdAt
                upvoteCount
                category {
                  name
                }
                author {
                  login
                }
                comments(first: 10) {
                  nodes {
                    id
                    body
                    createdAt
                    author {
                      login
                    }
                  }
                }
              }
            }
          }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": ["owner": owner, "repo": repo],
        ]
        let transport = GitHubRESTTransport(session: session, tokenProvider: { token })
        let request = transport.request(
            path: "graphql",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: payload)
        )
        let decoded: GraphQLDiscussionsResponse = try await transport.perform(request)
        guard let nodes = decoded.data?.repository?.discussions?.nodes else {
            return []
        }

        return nodes.map { node in
            DiscussionThread(
                id: node.id,
                title: node.title,
                author: node.author?.login ?? "anonymous",
                category: node.category?.name ?? "General",
                body: node.body ?? "",
                votes: node.upvoteCount ?? 0,
                replies: (node.comments?.nodes ?? []).map { comment in
                    DiscussionReply(
                        id: comment.id,
                        author: comment.author?.login ?? "anonymous",
                        body: comment.body ?? "",
                        isAccepted: false,
                        date: comment.createdAt
                    )
                },
                date: node.createdAt
            )
        }
    }

    // MARK: - Private helpers (Git Data API)

    private func getBranchRef(owner: String, repo: String, branch: String, transport: GitHubRESTTransport) async throws -> GitHubRefResponse {
        try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/git/ref/heads/\(transport.encode(branch))"
        ))
    }

    private func getCommitTreeSHA(owner: String, repo: String, commitSHA: String, transport: GitHubRESTTransport) async throws -> String {
        let response: GitHubCommitTreeResponse = try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/git/commits/\(transport.encode(commitSHA))"
        ))
        return response.tree.sha
    }

    private func createBlob(owner: String, repo: String, data: Data, transport: GitHubRESTTransport) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "content": data.base64EncodedString(),
            "encoding": "base64",
        ])
        let response: GitHubSHAOnlyResponse = try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/git/blobs",
            method: "POST",
            body: body
        ))
        return response.sha
    }

    private func createTree(owner: String, repo: String, baseTreeSHA: String, entries: [[String: Any]], transport: GitHubRESTTransport) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "base_tree": baseTreeSHA,
            "tree": entries,
        ])
        let response: GitHubSHAOnlyResponse = try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/git/trees",
            method: "POST",
            body: body
        ))
        return response.sha
    }

    private func createCommit(owner: String, repo: String, message: String, treeSHA: String, parentSHA: String, transport: GitHubRESTTransport) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "message": message,
            "tree": treeSHA,
            "parents": [parentSHA],
        ])
        let response: GitHubSHAOnlyResponse = try await transport.perform(transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/git/commits",
            method: "POST",
            body: body
        ))
        return response.sha
    }

    private func updateBranchRef(owner: String, repo: String, branch: String, commitSHA: String, transport: GitHubRESTTransport) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "sha": commitSHA,
            "force": false,
        ])
        let request = transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/git/refs/heads/\(transport.encode(branch))",
            method: "PATCH",
            body: body
        )
        try await transport.performVoid(request)
    }

    private func sanitizeWorkflowLogs(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\u{001B}\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "")
    }
}

/// Locked box for the token provider: the class is `@unchecked Sendable`,
/// so the mutable provider lives behind a lock.
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var provider: @Sendable () -> String? = { nil }

    func set(_ provider: @escaping @Sendable () -> String?) {
        lock.lock()
        defer { lock.unlock() }
        self.provider = provider
    }

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return provider()
    }
}

/// `GET /repos/{owner}/{repo}/git/ref/heads/{branch}` (Legacy's
/// `GitHubService.GitHubRefResponse` / `GitHubRefObject`, private here —
/// only the Git Data API push needs them).
private struct GitHubRefResponse: Decodable {
    let ref: String
    let object: GitHubRefObject
}

private struct GitHubRefObject: Decodable {
    let sha: String
    let type: String
}

/// `{"sha": ...}` — the blob / tree / commit creation responses.
private struct GitHubSHAOnlyResponse: Decodable {
    let sha: String
}

/// `GET /repos/{owner}/{repo}/git/commits/{sha}` (only the tree SHA is read).
private struct GitHubCommitTreeResponse: Decodable {
    let tree: GitHubSHAOnlyResponse
}

/// GraphQL discussions response (Legacy's `GraphQLDiscussionsResponse` and
/// its nested types, private — only `fetchDiscussions` decodes them).
private struct GraphQLDiscussionsResponse: Decodable {
    let data: GraphQLData?

    struct GraphQLData: Decodable {
        let repository: GraphQLRepository?
    }

    struct GraphQLRepository: Decodable {
        let discussions: GraphQLDiscussionsConnection?
    }

    struct GraphQLDiscussionsConnection: Decodable {
        let nodes: [GraphQLDiscussionNode]?
    }

    struct GraphQLDiscussionNode: Decodable {
        let id: String
        let title: String
        let body: String?
        let createdAt: String
        let upvoteCount: Int?
        let category: GraphQLCategory?
        let author: GraphQLAuthor?
        let comments: GraphQLCommentsConnection?
    }

    struct GraphQLCategory: Decodable {
        let name: String
    }

    struct GraphQLAuthor: Decodable {
        let login: String
    }

    struct GraphQLCommentsConnection: Decodable {
        let nodes: [GraphQLCommentNode]?
    }

    struct GraphQLCommentNode: Decodable {
        let id: String
        let body: String?
        let createdAt: String
        let author: GraphQLAuthor?
    }
}
