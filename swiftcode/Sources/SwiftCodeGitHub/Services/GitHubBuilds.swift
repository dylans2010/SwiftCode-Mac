import Foundation

extension GitHubClient {

    public func fetchLogContent(owner: String, repo: String, runID: Int) async throws -> String {
        let logsURL = try await getWorkflowRunLogsURL(owner: owner, repo: repo, runID: runID)
        let (data, _) = try await URLSession.shared.data(from: logsURL)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}

extension GitHubWorkflowRun {

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
