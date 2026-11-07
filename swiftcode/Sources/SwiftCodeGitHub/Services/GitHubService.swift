import Foundation

public final class GitHubService: @unchecked Sendable {
    public static let shared = GitHubService()

    private let session: URLSession
    private let tokenBox = TokenBox()

    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { nil }) {
        self.session = session
        tokenBox.set(tokenProvider)
    }

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

    public func fetchRepositories(token: String) async throws -> [GitHubRepository] {
        guard !token.isEmpty else { throw GitHubError.missingToken }
        let transport = GitHubRESTTransport(session: session, tokenProvider: { token })
        let request = transport.request(path: "user/repos", query: [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "100"),
        ])
        return try await transport.perform(request)
    }

    public func isRepositoryEmpty(owner: String, repo: String) async throws -> Bool {
        let detail = try await client().getRepository(owner: owner, repo: repo)
        if (detail.size ?? 0) == 0 { return true }
        return try await client().listBranches(owner: owner, repo: repo).isEmpty
    }

    public func getRepository(owner: String, repo: String) async throws -> GitHubRepository {
        try requireToken()
        return try await client().getRepository(owner: owner, repo: repo)
    }

    public func listBranches(owner: String, repo: String) async throws -> [GitHubBranch] {
        try requireToken()
        return try await client().listBranches(owner: owner, repo: repo)
    }

    public func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepository {
        try requireToken()
        return try await client().createRepository(name: name, description: description, isPrivate: isPrivate)
    }

    public func getRepoTree(owner: String, repo: String, branch: String = "main") async throws -> [GitHubTreeEntry] {
        try requireToken()
        return try await client().getRepoTree(owner: owner, repo: repo, ref: branch)
    }

    public func getFileText(owner: String, repo: String, path: String, ref: String? = nil) async throws -> String {
        try requireToken()
        return try await client().getFileText(owner: owner, repo: repo, path: path, ref: ref)
    }

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

    public func initializeGitHubRepository(
        owner: String,
        repo: String,
        projectName: String,
        projectDescription: String,
        directoryURL: URL,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws {
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

    public func listCommits(owner: String, repo: String, branch: String = "main", perPage: Int = 10) async throws -> [GitHubCommit] {
        try requireToken()
        return try await client().listCommits(owner: owner, repo: repo, branch: branch, perPage: perPage)
    }

    public func fetchCommitDetail(owner: String, repo: String, sha: String) async throws -> GitHubCommitDetailResponse {
        try requireToken()
        let transport = transport()
        let request = transport.request(
            path: "repos/\(transport.encode(owner))/\(transport.encode(repo))/commits/\(transport.encode(sha))"
        )
        return try await transport.perform(request)
    }

    public func getBranch(owner: String, repo: String, branch: String) async throws -> GitHubBranch? {
        try requireToken()
        return try await client().listBranches(owner: owner, repo: repo).first { $0.name == branch }
    }

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

    public func pushProject(
        owner: String,
        repo: String,
        branch: String = "main",
        commitMessage: String,
        files: [(path: String, data: Data)]
    ) async throws {
        try requireToken()
        let transport = transport()

        let branchRef = try await getBranchRef(owner: owner, repo: repo, branch: branch, transport: transport)
        let baseTreeSHA = try await getCommitTreeSHA(owner: owner, repo: repo, commitSHA: branchRef.object.sha, transport: transport)

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

        let newTreeSHA = try await createTree(owner: owner, repo: repo, baseTreeSHA: baseTreeSHA, entries: treeEntries, transport: transport)

        let newCommitSHA = try await createCommit(owner: owner, repo: repo, message: commitMessage, treeSHA: newTreeSHA, parentSHA: branchRef.object.sha, transport: transport)

        try await updateBranchRef(owner: owner, repo: repo, branch: branch, commitSHA: newCommitSHA, transport: transport)
    }

    public func getFileSHA(owner: String, repo: String, path: String, branch: String? = nil) async throws -> String? {
        try requireToken()
        return try await client().getFileSHA(owner: owner, repo: repo, path: path, ref: branch)
    }

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

    public func listWorkflowRuns(owner: String, repo: String) async throws -> [GitHubWorkflowRun] {
        try requireToken()
        return try await client().listWorkflowRuns(owner: owner, repo: repo)
    }

    public func listWorkflowJobs(owner: String, repo: String, runID: Int) async throws -> [GitHubWorkflowJob] {
        try requireToken()
        return try await client().listWorkflowJobs(owner: owner, repo: repo, runID: runID)
    }

    public func getJobLogs(owner: String, repo: String, jobID: Int) async throws -> String {
        try requireToken()
        return sanitizeWorkflowLogs(try await client().getJobLogs(owner: owner, repo: repo, jobID: jobID))
    }

    public func listWorkflowArtifacts(owner: String, repo: String, runID: Int) async throws -> [GitHubArtifact] {
        try requireToken()
        return try await client().listWorkflowArtifacts(owner: owner, repo: repo, runID: runID)
    }

    public func downloadArtifact(owner: String, repo: String, artifactID: Int) async throws -> Data {
        try requireToken()
        return try await client().downloadArtifact(owner: owner, repo: repo, artifactID: artifactID)
    }

    public func listPullRequests(owner: String, repo: String) async throws -> [GitHubPullRequest] {
        try requireToken()
        return try await client().listPullRequests(owner: owner, repo: repo)
    }

    public func listReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
        try requireToken()
        return try await client().listReleases(owner: owner, repo: repo)
    }

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

private struct GitHubRefResponse: Decodable {
    let ref: String
    let object: GitHubRefObject
}

private struct GitHubRefObject: Decodable {
    let sha: String
    let type: String
}

private struct GitHubSHAOnlyResponse: Decodable {
    let sha: String
}

private struct GitHubCommitTreeResponse: Decodable {
    let tree: GitHubSHAOnlyResponse
}

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
