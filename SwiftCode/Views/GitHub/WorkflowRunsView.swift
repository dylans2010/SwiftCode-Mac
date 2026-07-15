import SwiftUI
import AppKit

@MainActor
struct WorkflowRunsView: View {
    let run: WorkflowRunSummary
    let project: Project?
    @Environment(\.dismiss) private var dismiss

    @State private var jobs: [WorkflowJob] = []
    @State private var artifacts: [GitHubArtifact] = []
    @State private var isLoading = false
    @State private var isLoadingArtifacts = false

    // Console logs state
    @State private var selectedJobID: Int?
    @State private var consoleLogsText = ""
    @State private var isFetchingLogs = false

    // Re-run workflow state
    @State private var isExecutingReRun = false
    @State private var executionOutput = ""

    // Downloading artifact tracking
    @State private var downloadingArtifactID: Int?

    private var ownerAndRepo: (String, String)? {
        guard let repoStr = project?.githubRepo, !repoStr.isEmpty else { return nil }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Workflow Run Specs", systemImage: "play.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)

                Spacer()

                Button("Re-run Workflows") {
                    executeReRun()
                }
                .buttonStyle(.bordered)
                .disabled(isExecutingReRun)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Contents HSplitView
            HSplitView {
                // Left Pane: Job and Step Hierarchies list
                VStack(alignment: .leading, spacing: 0) {
                    Text("JOB & STEP HIERARCHIES")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.04))

                    Divider()

                    if isLoading {
                        VStack {
                            Spacer()
                            ProgressView().controlSize(.small)
                            Text("Fetching run jobs...").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if jobs.isEmpty {
                        VStack {
                            Spacer()
                            Text("No jobs executed for this run.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(jobs) { job in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: job.conclusion == "success" ? "checkmark.circle.fill" : (job.isRunning ? "clock.fill" : "play.circle.fill"))
                                            .foregroundStyle(job.conclusion == "success" ? .green : .orange)

                                        Text(job.name)
                                            .font(.subheadline.bold())

                                        Spacer()

                                        Button(isFetchingLogs && selectedJobID == job.id ? "Fetching..." : "Logs") {
                                            selectedJobID = job.id
                                            fetchLogs(for: job)
                                        }
                                        .buttonStyle(.plain)
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                        .disabled(isFetchingLogs)
                                    }

                                    // Render step hierarchy indented
                                    if let steps = job.steps {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(steps, id: \.number) { step in
                                                HStack {
                                                    Image(systemName: step.conclusion == "success" ? "checkmark" : "play")
                                                        .font(.system(size: 8))
                                                        .foregroundStyle(step.conclusion == "success" ? .green : .orange)

                                                    Text(step.name)
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.leading, 14)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .frame(width: 250)
                .frame(maxHeight: .infinity)

                // Right Pane: Logs Terminal Console + Artifacts Browser
                VStack(spacing: 0) {
                    // Logs Terminal
                    VStack(alignment: .leading, spacing: 0) {
                        Text("LOGS TERMINAL CONSOLE")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.12))

                        Divider()

                        ScrollView {
                            Text(isExecutingReRun ? executionOutput : consoleLogsText)
                                .font(.system(size: 11, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: .infinity)
                        .background(Color.black.opacity(0.85))
                    }
                    .frame(maxHeight: .infinity)

                    Divider()

                    // Artifacts Browser segment
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BUILD ARTIFACTS BROWSER")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.04))

                        Divider()

                        if isLoadingArtifacts {
                            HStack {
                                Spacer()
                                ProgressView().controlSize(.small)
                                Text("Loading artifacts...").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .frame(height: 100)
                        } else if artifacts.isEmpty {
                            HStack {
                                Spacer()
                                Text("No artifacts produced by this run.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .frame(height: 100)
                        } else {
                            List {
                                ForEach(artifacts) { artifact in
                                    HStack {
                                        Image(systemName: "doc.zipper")
                                            .foregroundStyle(.cyan)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(artifact.name)
                                                .font(.caption.bold())
                                            Text(formatBytes(artifact.sizeInBytes))
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()

                                        Button(downloadingArtifactID == artifact.id ? "Downloading..." : "Download") {
                                            downloadArtifact(artifact)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(downloadingArtifactID != nil)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .frame(height: 100)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 750, height: 550)
        .onAppear {
            fetchJobs()
            fetchArtifacts()
        }
    }

    private func fetchJobs() {
        guard let (owner, repo) = ownerAndRepo else { return }

        isLoading = true
        Task {
            do {
                let fetched = try await GitHubService.shared.listWorkflowJobs(owner: owner, repo: repo, runID: run.id)
                self.jobs = fetched
                if let firstJob = fetched.first {
                    selectedJobID = firstJob.id
                    fetchLogs(for: firstJob)
                }
            } catch {
                self.consoleLogsText = "Failed to load workflow jobs: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func fetchLogs(for job: WorkflowJob) {
        guard let (owner, repo) = ownerAndRepo else { return }

        isFetchingLogs = true
        Task {
            do {
                let fetchedLogs = try await GitHubService.shared.getJobLogs(owner: owner, repo: repo, jobID: job.id)
                self.consoleLogsText = fetchedLogs.isEmpty ? "No logs returned for this job." : fetchedLogs
            } catch {
                self.consoleLogsText = "Failed to fetch logs: \(error.localizedDescription)"
            }
            isFetchingLogs = false
        }
    }

    private func fetchArtifacts() {
        guard let (owner, repo) = ownerAndRepo else { return }

        isLoadingArtifacts = true
        Task {
            do {
                let fetched = try await GitHubService.shared.listWorkflowArtifacts(owner: owner, repo: repo, runID: run.id)
                self.artifacts = fetched
            } catch {
                // silent failure, keep list empty
            }
            isLoadingArtifacts = false
        }
    }

    private func downloadArtifact(_ artifact: GitHubArtifact) {
        guard let (owner, repo) = ownerAndRepo else { return }

        downloadingArtifactID = artifact.id
        Task {
            do {
                let zipData = try await GitHubService.shared.downloadArtifact(owner: owner, repo: repo, artifactID: artifact.id)

                // Save to Downloads directory
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                let destURL = downloadsURL.appendingPathComponent(artifact.name.hasSuffix(".zip") ? artifact.name : "\(artifact.name).zip")

                try zipData.write(to: destURL, options: .atomic)

                showDownloadSuccess(name: artifact.name, path: destURL.path)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Download Failed"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            downloadingArtifactID = nil
        }
    }

    private func executeReRun() {
        guard let (owner, repo) = ownerAndRepo else { return }
        isExecutingReRun = true
        executionOutput = "Re-triggering workflow run ID: \(run.id) via GitHub API...\n"

        Task {
            do {
                guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else {
                    throw GitHubError.missingToken
                }
                let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/actions/runs/\(run.id)/rerun")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    executionOutput += "[Success] Workflow re-run triggered successfully!\n"
                    executionOutput += "[Running] GitHub is initiating jobs. Refresh in a few moments.\n"
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    fetchJobs()
                } else {
                    executionOutput += "[Failed] Server returned status: \((response as? HTTPURLResponse)?.statusCode ?? 0)\n"
                }
            } catch {
                executionOutput += "[Failed] \(error.localizedDescription)\n"
            }
            isExecutingReRun = false
        }
    }

    private func showDownloadSuccess(name: String, path: String) {
        let alert = NSAlert()
        alert.messageText = "Artifact Download Complete"
        alert.informativeText = "Successfully saved '\(name)' to:\n\(path)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
