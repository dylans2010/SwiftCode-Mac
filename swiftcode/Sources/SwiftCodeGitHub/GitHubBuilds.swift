// Ported from SwiftCode-Legacy `SwiftCode/Backend/GitHub/GitHubBuilds.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Legacy `GitHubBuilds` fetched Actions workflow runs, logs and releases
// through `GitHubAPIBackend`. Most of its surface is already covered in
// the destination:
//
// - `fetchWorkflowRuns(owner:repo:)` → `GitHubClient.listWorkflowRuns`
// - `fetchLogsURL(owner:repo:runID:)` → `GitHubClient.getWorkflowRunLogsURL`
// - `fetchReleases(owner:repo:)` → `GitHubClient.listReleases`
// - `isRunning(_:)` → `GitHubWorkflowRun.isRunning` (computed property
//   on the model, same `in_progress` / `queued` check)
//
// The two missing pieces are staged here:
//
// - `fetchLogContent(owner:repo:runID:)` — downloads the run's logs as a
//   string. `getWorkflowRunLogsURL` already follows GitHub's 302 to the
//   short-lived download URL with auth, and that URL needs no further
//   auth, so the download is a plain `URLSession` fetch decoded as
//   UTF-8, falling back to ISO-Latin-1, as in Legacy. (Per-job plain-text
//   logs are the better API and already exist as `getJobLogs`; this is
//   the whole-run equivalent Legacy callers used.)
// - `statusSummary` — Legacy's human-readable status string for a run.
//   Ported as a computed property on `GitHubWorkflowRun`, next to the
//   existing `isRunning` / `statusBadge` helpers.

import Foundation

extension GitHubClient {

    /// Download the log content for a workflow run as a string
    /// (Legacy `GitHubBuilds.fetchLogContent`).
    public func fetchLogContent(owner: String, repo: String, runID: Int) async throws -> String {
        let logsURL = try await getWorkflowRunLogsURL(owner: owner, repo: repo, runID: runID)
        let (data, _) = try await URLSession.shared.data(from: logsURL)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}

extension GitHubWorkflowRun {

    /// A human-readable status string for this run
    /// (Legacy `GitHubBuilds.statusSummary(for:)`).
    public var statusSummary: String {
        switch conclusion ?? status {
        case "success": return "Succeeded"
        case "failure": return "Failed"
        case "cancelled": return "Cancelled"
        case "in_progress": return "Running"
        case "queued": return "Queued"
        default: return status.capitalized
        }
    }
}
