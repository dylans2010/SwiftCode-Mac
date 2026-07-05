import Foundation

final class GitHubAPIBackend {
    static let shared = GitHubAPIBackend()
    private init() {}

    private let baseURL = URL(string: "https://api.github.com")!


    func getAuthenticatedUser() async throws -> GitHubUser {
        let url = baseURL.appendingPathComponent("user")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try snakeCaseDecoder().decode(GitHubUser.self, from: data)
    }


    func getRepository(owner: String, repo: String) async throws -> GitHubRepoDetail {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try snakeCaseDecoder().decode(GitHubRepoDetail.self, from: data)
    }


    func listBranches(owner: String, repo: String) async throws -> [GitHubBranch] {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/branches")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode([GitHubBranch].self, from: data)
    }

    // MARK: - Commits

    func listCommits(owner: String, repo: String, branch: String = "main", perPage: Int = 20) async throws -> [GitHubCommit] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("repos/\(owner)/\(repo)/commits"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "sha", value: branch),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        let request = GitHubAuth.shared.authorizedRequest(url: components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try snakeCaseDecoder().decode([GitHubCommit].self, from: data)
    }

    // MARK: - File Operations

    func getFileContent(owner: String, repo: String, path: String) async throws -> String {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GitHubAPIError.invalidPath
        }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/contents/\(encoded)")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let file = try JSONDecoder().decode(GitHubFileContent.self, from: data)
        guard let decoded = Data(base64Encoded: file.content.replacingOccurrences(of: "\n", with: "")),
              let content = String(data: decoded, encoding: .utf8) else {
            throw GitHubAPIError.decodingFailed
        }
        return content
    }

    func getFileSHA(owner: String, repo: String, path: String) async throws -> String? {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/contents/\(encoded)")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(GitHubFileContent.self, from: data).sha
    }

    func pushFile(owner: String, repo: String, path: String, content: String, message: String, sha: String? = nil) async throws {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GitHubAPIError.invalidPath
        }
        let url = baseURL
            .appendingPathComponent("repos/\(owner)/\(repo)/contents/\(encoded)")
        var request = GitHubAuth.shared.authorizedRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "message": message,
            "content": Data(content.utf8).base64EncodedString()
        ]
        if let sha { body["sha"] = sha }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    // MARK: - Repository Tree

    func getRepoTree(owner: String, repo: String, branch: String = "main") async throws -> [GitHubTreeEntry] {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/git/trees/\(branch)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        let request = GitHubAuth.shared.authorizedRequest(url: components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(GitHubTreeResponse.self, from: data).tree
    }

    // MARK: - Workflow Runs

    func listWorkflowRuns(owner: String, repo: String) async throws -> [WorkflowRun] {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try snakeCaseDecoder().decode(WorkflowRunsResponse.self, from: data).workflowRuns
    }

    func getWorkflowRunLogsURL(owner: String, repo: String, runID: Int) async throws -> URL {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs/\(runID)/logs")
        var request = GitHubAuth.shared.authorizedRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .default, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 302,
              let location = http.value(forHTTPHeaderField: "Location"),
              let logsURL = URL(string: location) else {
            throw GitHubAPIError.noLogsAvailable
        }
        return logsURL
    }

    // MARK: - Workflow Artifacts

    func listWorkflowArtifacts(owner: String, repo: String, runID: Int) async throws -> [GitHubArtifact] {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs/\(runID)/artifacts")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try snakeCaseDecoder().decode(GitHubArtifactsResponse.self, from: data).artifacts
    }

    func downloadArtifact(owner: String, repo: String, artifactID: Int) async throws -> Data {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/artifacts/\(artifactID)/zip")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    // MARK: - Workflow Jobs

    func listWorkflowJobs(owner: String, repo: String, runID: Int) async throws -> [WorkflowJob] {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs/\(runID)/jobs")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try snakeCaseDecoder().decode(WorkflowJobsResponse.self, from: data).jobs
    }

    func getJobLogs(owner: String, repo: String, jobID: Int) async throws -> String {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/jobs/\(jobID)/logs")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Workflow Run (Single)

    func getWorkflowRun(owner: String, repo: String, runID: Int) async throws -> WorkflowRun {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs/\(runID)")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try snakeCaseDecoder().decode(WorkflowRun.self, from: data)
    }

    // MARK: - Releases

    func listReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/releases")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try snakeCaseDecoder().decode([GitHubRelease].self, from: data)
    }

    // MARK: - Download ZIP

    func downloadRepositoryZip(owner: String, repo: String, branch: String = "main") async throws -> URL {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/zipball/\(branch)")
        let request = GitHubAuth.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        let safeBranch = branch
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = docsURL.appendingPathComponent("\(repo)-\(safeBranch).zip")
        try data.write(to: destURL, options: .atomic)
        return destURL
    }

    // MARK: - Create Repository

    func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepo {
        let url = baseURL.appendingPathComponent("user/repos")
        var request = GitHubAuth.shared.authorizedRequest(url: url, method: "POST")
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

    // MARK: - Validation

    func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GitHubAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubAPIError.apiError(statusCode: http.statusCode, body: body)
        }
    }

    // MARK: - Helpers

    private func snakeCaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - No-Redirect Delegate

private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? { nil }
}

// MARK: - Errors

enum GitHubAPIError: LocalizedError {
    case missingToken
    case invalidResponse
    case apiError(statusCode: Int, body: String)
    case noLogsAvailable
    case invalidPath
    case decodingFailed

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
        }
    }
}
