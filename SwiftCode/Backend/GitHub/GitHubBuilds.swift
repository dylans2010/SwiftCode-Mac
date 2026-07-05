import Foundation

/// Fetches GitHub Actions workflow runs, build statuses, timestamps, and logs.
///
/// All data is fetched via GitHubAPIBackend and the results are ready to display
/// in the GitHub integration view.
final class GitHubBuilds {
    static let shared = GitHubBuilds()
    private init() {}

    // MARK: - Workflow Runs

    /// Fetch the most recent workflow runs for a repository.
    func fetchWorkflowRuns(owner: String, repo: String) async throws -> [WorkflowRun] {
        try await GitHubAPIBackend.shared.listWorkflowRuns(owner: owner, repo: repo)
    }

    /// Fetch workflow runs from a full GitHub repository URL.
    func fetchWorkflowRuns(from urlString: String) async throws -> [WorkflowRun] {
        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(urlString)
        return try await fetchWorkflowRuns(owner: owner, repo: repo)
    }

    // MARK: - Build Logs

    /// Retrieve the download URL for logs of a specific workflow run.
    func fetchLogsURL(owner: String, repo: String, runID: Int) async throws -> URL {
        try await GitHubAPIBackend.shared.getWorkflowRunLogsURL(owner: owner, repo: repo, runID: runID)
    }

    /// Download the log content for a specific workflow run as a string.
    func fetchLogContent(owner: String, repo: String, runID: Int) async throws -> String {
        let logsURL = try await fetchLogsURL(owner: owner, repo: repo, runID: runID)
        let (data, _) = try await URLSession.shared.data(from: logsURL)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Build Status Summary

    /// Return a human-readable status string for a workflow run.
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

    /// Returns true if the run represents an active (non-terminal) workflow.
    func isRunning(_ run: WorkflowRun) -> Bool {
        run.status == "in_progress" || run.status == "queued"
    }

    // MARK: - Releases

    /// Fetch recent releases for a repository.
    func fetchReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
        try await GitHubAPIBackend.shared.listReleases(owner: owner, repo: repo)
    }
}
