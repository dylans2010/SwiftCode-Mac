import SwiftCodeGitHub
import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/WorkflowRunsView.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// The missing slice of the workflow-run detail: the run-specs header and
/// the artifacts browser. The destination CI window (`CIWindowController`,
/// AppKit) already covers runs, jobs, logs, and re-run; it has no artifacts
/// section, and no run-specs header.
///
/// - `WorkflowRunSpecsHeaderView`: run name, status summary, branch, and
///   Re-run / Done actions. Re-run uses the real
///   `GitHubClient.rerunWorkflow`; Done dismisses.
/// - `WorkflowRunArtifactsView`: lists the run's artifacts via
///   `GitHubClient.listWorkflowArtifacts` (name, size, expired state) and
///   downloads the chosen one via `GitHubClient.downloadArtifact`,
///   saving `<name>.zip` into Downloads with success/failure feedback
///   (the Legacy pattern).
///
/// Hook: host both in the CI window's run-detail area via
/// NSHostingController (the window is AppKit; these views are SwiftUI),
/// passing the window's `GitHubClient` and the selected run's identity.
@MainActor
public struct WorkflowRunSpecsHeaderView: View {
    public var run: SwiftCodeGitHub.GitHubWorkflowRun
    public var client: GitHubClient
    public var owner: String
    public var repo: String
    public var onDone: () -> Void

    @State private var isRerunning = false
    @State private var message: String?

    public init(run: SwiftCodeGitHub.GitHubWorkflowRun, client: GitHubClient, owner: String, repo: String, onDone: @escaping () -> Void) {
        self.run = run
        self.client = client
        self.owner = owner
        self.repo = repo
        self.onDone = onDone
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.name ?? "Workflow Run")
                    .font(.headline)
                Text("Run #\(run.runNumber) · \(run.headBranch ?? "—") · \(run.statusSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Re-run") {
                Task { await rerun() }
            }
            .buttonStyle(.bordered)
            .disabled(isRerunning)
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func rerun() async {
        isRerunning = true
        message = nil
        defer { isRerunning = false }
        do {
            try await client.rerunWorkflow(owner: owner, repo: repo, runID: run.id)
            message = "Re-run started."
        } catch {
            message = "Re-run failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
public struct WorkflowRunArtifactsView: View {
    public var client: GitHubClient
    public var owner: String
    public var repo: String
    public var runID: Int

    @State private var artifacts: [GitHubArtifact] = []
    @State private var isLoading = false
    @State private var downloadingID: Int?
    @State private var message: String?
    @State private var errorMessage: String?

    public init(client: GitHubClient, owner: String, repo: String, runID: Int) {
        self.client = client
        self.owner = owner
        self.repo = repo
        self.runID = runID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Artifacts")
                .font(.headline)

            if isLoading {
                ProgressView("Loading artifacts…")
                    .controlSize(.small)
            } else if artifacts.isEmpty {
                Text("This run has no artifacts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(artifacts) { artifact in
                    HStack {
                        Image(systemName: artifact.expired ? "doc.zipper" : "archivebox")
                            .foregroundStyle(artifact.expired ? .secondary : .accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(artifact.name)
                                .font(.subheadline)
                            Text(artifact.expired ? "Expired" : byteCount(artifact.sizeInBytes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(downloadingID == artifact.id ? "Downloading…" : "Download") {
                            Task { await download(artifact) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(artifact.expired || downloadingID != nil)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .task { await load() }
    }

    private func byteCount(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
        return "\(bytes) bytes"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            artifacts = try await client.listWorkflowArtifacts(owner: owner, repo: repo, runID: runID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func download(_ artifact: GitHubArtifact) async {
        downloadingID = artifact.id
        message = nil
        errorMessage = nil
        defer { downloadingID = nil }
        do {
            let data = try await client.downloadArtifact(owner: owner, repo: repo, artifactID: artifact.id)
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let destination = downloads.appendingPathComponent("\(artifact.name).zip")
            try data.write(to: destination)
            message = "Downloaded \(artifact.name).zip to Downloads."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
