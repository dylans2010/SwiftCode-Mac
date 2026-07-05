import Foundation

// MARK: - GitHub API Service

final class GitHubService {
    static let shared = GitHubService()
    private init() {}

    private let baseURL = URL(string: "https://api.github.com")!

    private var token: String? {
        APIKeyManager.shared.retrieveKey(service: .gitHub) ?? KeychainService.shared.get(forKey: KeychainService.githubToken)
    }

    private func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Validate & Fetch Repository Info

    /// Validates whether a GitHub repository URL points to a real repo and returns its details.
    func validateAndFetchRepo(owner: String, repo: String) async throws -> GitHubRepoDetail {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRepoDetail.self, from: data)
    }

    // MARK: - List Commits

    func listCommits(owner: String, repo: String, branch: String = "main", perPage: Int = 10) async throws -> [GitHubCommit] {
        guard token != nil else { throw GitHubError.missingToken }
        var components = URLComponents(url: baseURL.appendingPathComponent("repos/\(owner)/\(repo)/commits"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sha", value: branch),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        let request = authorizedRequest(url: components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitHubCommit].self, from: data)
    }

    // MARK: - Get Repository Tree (for file listing)

    func getRepoTree(owner: String, repo: String, branch: String = "main") async throws -> [GitHubTreeEntry] {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/trees/\(branch)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        let request = authorizedRequest(url: components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let decoded = try JSONDecoder().decode(GitHubTreeResponse.self, from: data)
        return decoded.tree
    }

    // MARK: - Auth Check

    func getAuthenticatedUser() async throws -> GitHubUser {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("user")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    // MARK: - Create Repository

    func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepo {
        guard token != nil else { throw GitHubError.missingToken }

        let url = baseURL.appendingPathComponent("user/repos")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": name,
            "description": description,
            "private": isPrivate,
            "auto_init": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(GitHubRepo.self, from: data)
    }

    // MARK: - Push File (create or update)

    func pushFile(
        owner: String,
        repo: String,
        path: String,
        content: String,
        message: String,
        sha: String? = nil,
        branch: String? = nil
    ) async throws {
        guard token != nil else { throw GitHubError.missingToken }

        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GitHubError.invalidPath
        }
        let url = baseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(owner)
            .appendingPathComponent(repo)
            .appendingPathComponent("contents")
            .appendingPathComponent(encodedPath)

        var request = authorizedRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Content = Data(content.utf8).base64EncodedString()
        var body: [String: Any] = [
            "message": message,
            "content": base64Content
        ]
        if let sha { body["sha"] = sha }
        if let branch { body["branch"] = branch }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    // MARK: - Push All Project Files (Efficient Data API)

    func pushProject(_ project: Project, owner: String, repo: String, commitMessage: String, branch: String = "main") async throws {
        let allFiles = collectFiles(from: project.files)
        let projectDir = await project.directoryURL

        // 1. Get the latest commit SHA of the branch
        let branchRef = try await getBranchRef(owner: owner, repo: repo, branch: branch)
        let baseTreeSHA = try await getCommitTreeSHA(owner: owner, repo: repo, commitSHA: branchRef.object.sha)

        // 2. Create blobs for each file
        var treeEntries: [[String: Any]] = []
        for fileNode in allFiles {
            let fileURL = projectDir.appendingPathComponent(fileNode.path)
            let data = try Data(contentsOf: fileURL)
            let blobSHA = try await createBlob(owner: owner, repo: repo, data: data)

            treeEntries.append([
                "path": fileNode.path,
                "mode": "100644",
                "type": "blob",
                "sha": blobSHA
            ])
        }

        // 3. Create a new tree
        let newTreeSHA = try await createTree(owner: owner, repo: repo, baseTreeSHA: baseTreeSHA, entries: treeEntries)

        // 4. Create a new commit
        let newCommitSHA = try await createCommit(owner: owner, repo: repo, message: commitMessage, treeSHA: newTreeSHA, parentSHA: branchRef.object.sha)

        // 5. Update the branch reference
        try await updateBranchRef(owner: owner, repo: repo, branch: branch, commitSHA: newCommitSHA)
    }

    private func getBranchRef(owner: String, repo: String, branch: String) async throws -> GitHubRefResponse {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/ref/heads/\(branch)")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(GitHubRefResponse.self, from: data)
    }

    private func getCommitTreeSHA(owner: String, repo: String, commitSHA: String) async throws -> String {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/commits/\(commitSHA)")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let tree = json?["tree"] as? [String: Any], let sha = tree["sha"] as? String else {
            throw GitHubError.decodingFailed
        }
        return sha
    }

    private func createBlob(owner: String, repo: String, data: Data) async throws -> String {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/blobs")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "content": data.base64EncodedString(),
            "encoding": "base64"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: responseData)
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        return json?["sha"] as? String ?? ""
    }

    private func createTree(owner: String, repo: String, baseTreeSHA: String, entries: [[String: Any]]) async throws -> String {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/trees")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "base_tree": baseTreeSHA,
            "tree": entries
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: responseData)
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        return json?["sha"] as? String ?? ""
    }

    private func createCommit(owner: String, repo: String, message: String, treeSHA: String, parentSHA: String) async throws -> String {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/commits")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "message": message,
            "tree": treeSHA,
            "parents": [parentSHA]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: responseData)
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        return json?["sha"] as? String ?? ""
    }

    private func updateBranchRef(owner: String, repo: String, branch: String, commitSHA: String) async throws {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/refs/heads/\(branch)")
        var request = authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "sha": commitSHA,
            "force": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    struct GitHubRefResponse: Decodable {
        let ref: String
        let object: GitHubRefObject
    }

    struct GitHubRefObject: Decodable {
        let sha: String
        let type: String
    }

    private func collectFiles(from nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { node -> [FileNode] in
            if node.isDirectory { return collectFiles(from: node.children) }
            return [node]
        }
    }

    // MARK: - Get File SHA

    func getFileSHA(owner: String, repo: String, path: String, branch: String? = nil) async throws -> String? {
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var url = baseURL
            .appendingPathComponent("repos/\(owner)/\(repo)/contents/\(encodedPath)")

        if let branch {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "ref", value: branch)]
            if let branchURL = components?.url {
                url = branchURL
            }
        }

        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let json = try JSONDecoder().decode(GitHubFileContent.self, from: data)
        return json.sha
    }

    // MARK: - List Workflow Runs

    func listWorkflowRuns(owner: String, repo: String) async throws -> [WorkflowRun] {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(WorkflowRunsResponse.self, from: data)
        return result.workflowRuns
    }

    // MARK: - Get Workflow Run Logs URL

    func getWorkflowRunLogsURL(owner: String, repo: String, runID: Int) async throws -> URL {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs/\(runID)/logs")
        var request = authorizedRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // This endpoint returns a redirect; capture the Location header.
        let session = URLSession(configuration: .default, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 302,
              let locationString = httpResponse.value(forHTTPHeaderField: "Location"),
              let logsURL = URL(string: locationString) else {
            throw GitHubError.noLogsAvailable
        }
        return logsURL
    }

    // MARK: - Workflow Artifacts

    func listWorkflowArtifacts(owner: String, repo: String, runID: Int) async throws -> [GitHubArtifact] {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs/\(runID)/artifacts")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubArtifactsResponse.self, from: data).artifacts
    }

    func downloadArtifact(owner: String, repo: String, artifactID: Int) async throws -> Data {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/artifacts/\(artifactID)/zip")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    // MARK: - Workflow Jobs

    func listWorkflowJobs(owner: String, repo: String, runID: Int) async throws -> [WorkflowJob] {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs/\(runID)/jobs")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkflowJobsResponse.self, from: data).jobs
    }

    func getJobLogs(owner: String, repo: String, jobID: Int) async throws -> String {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/jobs/\(jobID)/logs")
        var request = authorizedRequest(url: url)
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return sanitizeWorkflowLogs(utf8)
        }

        if let latin1 = String(data: data, encoding: .isoLatin1), !latin1.isEmpty {
            return sanitizeWorkflowLogs(latin1)
        }

        return ""
    }

    private func sanitizeWorkflowLogs(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\u{001B}\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "")
    }

    // MARK: - Workflow Run (Single)

    func getWorkflowRun(owner: String, repo: String, runID: Int) async throws -> WorkflowRun {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs/\(runID)")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkflowRun.self, from: data)
    }

    // MARK: - List Branches

    func listBranches(owner: String, repo: String) async throws -> [GitHubBranch] {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/branches")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode([GitHubBranch].self, from: data)
    }

    func getBranch(owner: String, repo: String, branch: String) async throws -> GitHubBranch? {
        let branches = try await listBranches(owner: owner, repo: repo)
        return branches.first { $0.name == branch }
    }

    func isRepositoryEmpty(owner: String, repo: String) async throws -> Bool {
        let repoDetail = try await validateAndFetchRepo(owner: owner, repo: repo)
        // If size is 0 or default branch is empty/missing, it's likely empty
        if (repoDetail.size ?? 0) == 0 { return true }

        // Double check branches
        let branches = try await listBranches(owner: owner, repo: repo)
        return branches.isEmpty
    }

    func initializeGitHubRepository(for project: Project, logHandler: @escaping (String) -> Void) async throws {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            throw GitHubError.pushFailed(message: "No GitHub repository linked to this project.")
        }

        let components = repoURL.split(separator: "/")
        guard components.count >= 2 else {
            throw GitHubError.pushFailed(message: "Invalid repository format: \(repoURL)")
        }
        let owner = String(components[0])
        let repo = String(components[1])
        let projectDir = await project.directoryURL

        // Step 1: Detect and scan
        logHandler("Scanning template files")
        var filesToUpload: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: projectDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues?.isRegularFile == true {
                // Skip project.json metadata
                if fileURL.lastPathComponent != "project.json" {
                    filesToUpload.append(fileURL)
                }
            }
        }

        // Step 2: Create the GitHub repository
        logHandler("Creating GitHub repository")
        do {
            _ = try await createRepository(name: repo, description: project.description, isPrivate: false)
            logHandler("Repository created successfully")
        } catch {
            // If it already exists (422), we can proceed
            if case let .apiError(statusCode, _) = error as? GitHubError, statusCode == 422 {
                logHandler("Repository created successfully")
            } else {
                logHandler("Repository creation: \(error.localizedDescription)")
            }
        }

        // Step 3: Create initial commit
        logHandler("Creating initial commit")
        let readmeURL = projectDir.appendingPathComponent("README.md")
        let readmeContent: String
        if FileManager.default.fileExists(atPath: readmeURL.path) {
            readmeContent = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? "# \(project.name)\n\nCreated with SwiftCode."
        } else {
            readmeContent = "# \(project.name)\n\nCreated with SwiftCode."
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
            let relativePath = String(fileURL.path.dropFirst(projectDir.path.count + 1))
            // README already pushed or will be updated if it was in the scanned list
            if relativePath == "README.md" { continue }

            let data = try Data(contentsOf: fileURL)
            // Use SHA to avoid 409 if file exists
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

    func initializeRepository(owner: String, repo: String, branch: String = "main") async throws {
        let readmeContent = "# \(repo)\n\nCreated by SwiftCode."
        try await pushFile(
            owner: owner,
            repo: repo,
            path: "README.md",
            content: readmeContent,
            message: "Initial commit created by SwiftCode",
            branch: branch
        )
    }

    func createBranchRef(owner: String, repo: String, branch: String, sha: String) async throws {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/refs")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "ref": "refs/heads/\(branch)",
            "sha": sha
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    func pushFileData(
        owner: String,
        repo: String,
        path: String,
        data: Data,
        message: String,
        sha: String? = nil,
        branch: String? = nil
    ) async throws {
        guard token != nil else { throw GitHubError.missingToken }

        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GitHubError.invalidPath
        }
        let url = baseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(owner)
            .appendingPathComponent(repo)
            .appendingPathComponent("contents")
            .appendingPathComponent(encodedPath)

        var request = authorizedRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Content = data.base64EncodedString()
        var body: [String: Any] = [
            "message": message,
            "content": base64Content
        ]
        if let sha { body["sha"] = sha }
        if let branch { body["branch"] = branch }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: responseData)
    }

    func pushProjectUsingContentsAPI(
        project: Project,
        owner: String,
        repo: String,
        branch: String = "main",
        logHandler: (String) -> Void
    ) async throws {
        let allFiles = collectFiles(from: project.files)
        let projectDir = await project.directoryURL

        for fileNode in allFiles {
            let fileURL = projectDir.appendingPathComponent(fileNode.path)
            let data = try Data(contentsOf: fileURL)

            logHandler("Uploading: \(fileNode.path)")

            let existingSHA = try? await getFileSHA(owner: owner, repo: repo, path: fileNode.path, branch: branch)

            try await pushFileData(
                owner: owner,
                repo: repo,
                path: fileNode.path,
                data: data,
                message: "Update \(fileNode.path)",
                sha: existingSHA,
                branch: branch
            )
        }
    }

    // MARK: - Create Branch

    /// Creates a new branch from an existing branch's HEAD SHA.
    /// PLACEHOLDER: Fetches the base branch SHA then POSTs a new ref.
    func createBranch(owner: String, repo: String, branchName: String, fromBranch: String) async throws {
        guard token != nil else { throw GitHubError.missingToken }

        // Step 1: Resolve the base branch SHA.
        // GET /repos/{owner}/{repo}/git/ref/heads/{fromBranch}
        let refURL = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/ref/heads/\(fromBranch)")
        let refRequest = authorizedRequest(url: refURL)
        let (refData, refResponse) = try await URLSession.shared.data(for: refRequest)
        try validateResponse(refResponse, data: refData)

        struct RefResponse: Decodable {
            struct RefObject: Decodable { let sha: String }
            let object: RefObject
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let refObj = try decoder.decode(RefResponse.self, from: refData)
        let sha = refObj.object.sha

        // Step 2: Create the new ref.
        // POST /repos/{owner}/{repo}/git/refs
        let createURL = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/refs")
        var createRequest = authorizedRequest(url: createURL, method: "POST")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["ref": "refs/heads/\(branchName)", "sha": sha]
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
        try validateResponse(createResponse, data: createData)
    }

    // MARK: - Delete Branch

    /// Deletes a branch by removing its ref.
    /// PLACEHOLDER: DELETE /repos/{owner}/{repo}/git/refs/heads/{branchName}
    func deleteBranch(owner: String, repo: String, branchName: String) async throws {
        guard token != nil else { throw GitHubError.missingToken }

        guard let encoded = branchName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GitHubError.invalidPath
        }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/refs/heads/\(encoded)")
        let request = authorizedRequest(url: url, method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: request)
        // 204 No Content is the expected success response for DELETE
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        guard http.statusCode == 204 || (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.apiError(statusCode: http.statusCode, body: body)
        }
    }

    // MARK: - Create Pull Request

    /// Creates a pull request on GitHub.
    /// PLACEHOLDER: POST /repos/{owner}/{repo}/pulls
    func createPullRequest(
        owner: String,
        repo: String,
        title: String,
        body: String,
        head: String,
        base: String,
        reviewers: [String] = [],
        labels: [String] = [],
        milestone: String = "",
        isDraft: Bool = false
    ) async throws -> GitHubPullRequest {
        guard token != nil else { throw GitHubError.missingToken }

        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/pulls")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyDict: [String: Any] = [
            "title": title,
            "body": body,
            "head": head,
            "base": base,
            "draft": isDraft
        ]
        // Reviewers and labels require separate API calls to add after PR creation.
        // PLACEHOLDER: POST /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
        //              POST /repos/{owner}/{repo}/issues/{issue_number}/labels
        _ = reviewers
        _ = labels
        _ = milestone

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubPullRequest.self, from: data)
    }

    // MARK: - Download Repository as ZIP (saves to device)

    /// Downloads the repository at the given branch as a ZIP and returns the local file URL.
    func downloadRepositoryZip(owner: String, repo: String, branch: String = "main") async throws -> URL {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/zipball/\(branch)")
        let request = authorizedRequest(url: url)
        // URLSession follows the redirect automatically and returns the ZIP data
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        // Sanitize branch name for use as filename (replace slashes and other invalid chars)
        let safeBranch = branch.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let repoFileName = "\(repo)-\(safeBranch).zip"
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = docsURL.appendingPathComponent(repoFileName)
        try data.write(to: destURL, options: .atomic)
        return destURL
    }

    // MARK: - List Releases

    func listReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/releases")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitHubRelease].self, from: data)
    }

    // MARK: - Pull / Download File

    func getFileContent(owner: String, repo: String, path: String) async throws -> String {
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GitHubError.invalidPath
        }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/contents/\(encodedPath)")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let file = try JSONDecoder().decode(GitHubFileContent.self, from: data)
        guard let decoded = Data(base64Encoded: file.content.replacingOccurrences(of: "\n", with: "")),
              let string = String(data: decoded, encoding: .utf8) else {
            throw GitHubError.decodingFailed
        }
        return string
    }

    // MARK: - List User Repositories

    /// Fetches repositories accessible to the authenticated user.
    func listUserRepositories(perPage: Int = 100) async throws -> [GitHubRepoSummary] {
        guard token != nil else { throw GitHubError.missingToken }
        var components = URLComponents(url: baseURL.appendingPathComponent("user/repos"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        let request = authorizedRequest(url: components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([GitHubRepoSummary].self, from: data)
    }

    // MARK: - Fetch Commit Detail (for diff preview)
    func fetchCommitDetail(owner: String, repo: String, sha: String) async throws -> GitHubCommitDetailResponse {
        guard token != nil else { throw GitHubError.missingToken }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/commits/\(sha)")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubCommitDetailResponse.self, from: data)
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.apiError(statusCode: http.statusCode, body: body)
        }
    }
}

// MARK: - No Redirect Delegate (for log URLs)

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil // Don't follow redirects
    }
}

// MARK: - GitHub Response Models

struct GitHubBranch: Identifiable, Decodable {
    var id: String { name }
    let name: String
    let protected: Bool
}

struct GitHubUser: Decodable {
    let login: String
    let name: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login, name
        case avatarUrl = "avatar_url"
    }
}

struct GitHubRepo: Decodable {
    let id: Int
    let name: String
    let fullName: String
    let htmlUrl: String
    let cloneUrl: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case cloneUrl = "clone_url"
    }
}

/// Lightweight summary of a user-accessible GitHub repository, used for the repo picker.
/// CodingKeys use camelCase raw values so they match keys after `keyDecodingStrategy = .convertFromSnakeCase`
/// converts the JSON snake_case keys (e.g. `full_name` → `fullName`).
struct GitHubRepoSummary: Identifiable, Decodable {
    let id: Int
    let name: String
    let fullName: String
    let htmlUrl: String
    let isPrivate: Bool
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, fullName, htmlUrl
        case isPrivate = "private"
    }
}

struct GitHubFileContent: Decodable {
    let sha: String
    let content: String
}

struct WorkflowRunsResponse: Decodable {
    let workflowRuns: [WorkflowRun]
}

struct WorkflowRun: Identifiable, Decodable {
    let id: Int
    let name: String?
    let status: String
    let conclusion: String?
    let htmlUrl: String
    let createdAt: Date
    let updatedAt: Date
    let runNumber: Int
    let headBranch: String?

    var statusBadge: String {
        switch conclusion ?? status {
        case "success": return "checkmark.circle.fill"
        case "failure": return "xmark.circle.fill"
        case "cancelled": return "slash.circle.fill"
        case "in_progress": return "clock.fill"
        default: return "circle"
        }
    }

    var isRunning: Bool {
        status == "in_progress" || status == "queued"
    }
}

struct GitHubRelease: Identifiable, Decodable {
    let id: Int
    let tagName: String
    let name: String?
    let htmlUrl: String
    let createdAt: Date
    let assets: [GitHubAsset]
}

struct GitHubAsset: Identifiable, Decodable {
    let id: Int
    let name: String
    let browserDownloadUrl: String
    let size: Int
}

struct GitHubRepoDetail: Decodable, Identifiable {
    let id: Int
    let name: String
    let fullName: String
    let htmlUrl: String
    let cloneUrl: String
    let description: String?
    let language: String?
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let defaultBranch: String?
    let isPrivate: Bool
    let size: Int?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description, language, size
        case fullName = "fullName"
        case htmlUrl = "htmlUrl"
        case cloneUrl = "cloneUrl"
        case stargazersCount = "stargazersCount"
        case forksCount = "forksCount"
        case openIssuesCount = "openIssuesCount"
        case defaultBranch = "defaultBranch"
        case isPrivate = "private"
        case createdAt = "createdAt"
        case updatedAt = "updatedAt"
    }
}

struct GitHubCommit: Identifiable, Decodable {
    let sha: String
    let commit: CommitDetail
    let htmlUrl: String?

    var id: String { sha }

    struct CommitDetail: Decodable {
        let message: String
        let author: AuthorInfo?

        struct AuthorInfo: Decodable {
            let name: String?
            let date: Date?
        }
    }
}

struct GitHubTreeResponse: Decodable {
    let sha: String
    let tree: [GitHubTreeEntry]
}

struct GitHubTreeEntry: Identifiable, Decodable {
    let path: String
    let type: String
    let sha: String
    let size: Int?

    var id: String { sha + path }
}

// MARK: - Pull Request Model

struct GitHubPullRequest: Identifiable, Decodable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let htmlUrl: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state
        case htmlUrl = "html_url"
    }
}

// MARK: - Commit Detail Model

struct GitHubArtifactsResponse: Decodable {
    let artifacts: [GitHubArtifact]
}

struct GitHubArtifact: Identifiable, Decodable {
    let id: Int
    let name: String
    let sizeInBytes: Int
    let archiveDownloadUrl: String?
    let expired: Bool
}

struct WorkflowJobsResponse: Decodable {
    let jobs: [WorkflowJob]
}

struct WorkflowJob: Identifiable, Decodable {
    let id: Int
    let runId: Int
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let name: String
    let steps: [WorkflowStep]?

    var isRunning: Bool {
        status == "in_progress" || status == "queued"
    }
}

struct WorkflowStep: Decodable {
    let name: String
    let status: String
    let conclusion: String?
    let number: Int
}

struct GitHubCommitDetailResponse: Decodable {
    let sha: String
    let files: [GitHubCommitFile]?

    struct GitHubCommitFile: Decodable {
        let filename: String
        let status: String
        let additions: Int
        let deletions: Int
        let patch: String?
    }
}

// MARK: - Errors

enum GitHubError: LocalizedError {
    case missingToken
    case invalidResponse
    case apiError(statusCode: Int, body: String)
    case noLogsAvailable
    case invalidPath
    case decodingFailed
    case pushFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No GitHub token found. Please add your personal access token in Settings."
        case .invalidResponse:
            return "Received an invalid response from GitHub."
        case let .apiError(code, body):
            return "GitHub API error \(code): \(body)"
        case .noLogsAvailable:
            return "No logs are available for this workflow run."
        case .invalidPath:
            return "The file path is invalid."
        case .decodingFailed:
            return "Failed to decode file content from GitHub."
        case .pushFailed(let message):
            return message
        }
    }
}
