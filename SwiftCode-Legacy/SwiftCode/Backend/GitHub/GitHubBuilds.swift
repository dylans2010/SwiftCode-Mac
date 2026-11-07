import Foundation

final class GitHubBuilds: @unchecked Sendable {
    static let shared = GitHubBuilds()
    private init() {}

    func fetchWorkflowRuns(owner: String, repo: String) async throws -> [WorkflowRun] {
        try await GitHubAPIBackend.shared.listWorkflowRuns(owner: owner, repo: repo)
    }

    func fetchWorkflowRuns(from urlString: String) async throws -> [WorkflowRun] {
        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(urlString)
        return try await fetchWorkflowRuns(owner: owner, repo: repo)
    }

    func fetchLogsURL(owner: String, repo: String, runID: Int) async throws -> URL {
        try await GitHubAPIBackend.shared.getWorkflowRunLogsURL(owner: owner, repo: repo, runID: runID)
    }

    func fetchLogContent(owner: String, repo: String, runID: Int) async throws -> String {
        let logsURL = try await fetchLogsURL(owner: owner, repo: repo, runID: runID)
        let (data, _) = try await URLSession.shared.data(from: logsURL)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    func statusSummary(for run: WorkflowRun) -> String {
        switch run.conclusion ?? run.status {
        case "success":  return "Succeeded"
        case "failure":  return "Failed"
        case "cancelled": return "Cancelled"
        case "in_progress": return "Running"
        case "queued":   return "Queued"
        default:         return run.status.capitalized
        }
    }

    func isRunning(_ run: WorkflowRun) -> Bool {
        run.status == "in_progress" || run.status == "queued"
    }

    func fetchReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
        try await GitHubAPIBackend.shared.listReleases(owner: owner, repo: repo)
    }
}
