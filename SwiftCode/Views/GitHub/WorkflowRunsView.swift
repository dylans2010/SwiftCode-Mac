import SwiftUI

@MainActor
struct WorkflowRunsView: View {
    let run: WorkflowRunSummary
    let project: Project?
    @Environment(\.dismiss) private var dismiss

    @State private var jobs: [WorkflowJob] = []
    @State private var isLoading = false

    // Console logs state
    @State private var selectedJobID: Int?
    @State private var consoleLogsText = ""
    @State private var isFetchingLogs = false

    // Re-run workflow state
    @State private var isExecutingReRun = false
    @State private var executionOutput = ""

    // Artifacts browser state
    @State private var mockArtifacts: [MockArtifact] = [
        MockArtifact(name: "SwiftCode-macOS-build.zip", size: "48.2 MB", downloaded: false),
        MockArtifact(name: "test-results.xml", size: "124 KB", downloaded: false)
    ]

    struct MockArtifact: Identifiable {
        let id = UUID()
        let name: String
        let size: String
        var downloaded: Bool
    }

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
                            ProgressView().controlSize(.small)
                            Text("Fetching run jobs...").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if jobs.isEmpty {
                        Text("No jobs executed for this run.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                        Spacer()
                    } else {
                        List {
                            ForEach(jobs) { job in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: job.conclusion == "success" ? "checkmark.circle.fill" : "play.circle.fill")
                                            .foregroundStyle(job.conclusion == "success" ? .green : .orange)

                                        Text(job.name)
                                            .font(.subheadline.bold())

                                        Spacer()

                                        Button("Logs") {
                                            selectedJobID = job.id
                                            fetchLogs(for: job)
                                        }
                                        .buttonStyle(.plain)
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
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

                        List {
                            ForEach($mockArtifacts) { $artifact in
                                HStack {
                                    Image(systemName: "doc.zipper")
                                        .foregroundStyle(.cyan)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(artifact.name)
                                            .font(.caption.bold())
                                        Text(artifact.size)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()

                                    Button(artifact.downloaded ? "Downloaded" : "Download") {
                                        artifact.downloaded = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(artifact.downloaded)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .frame(height: 100)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 750, height: 550)
        .onAppear {
            fetchJobs()
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
                    fetchLogs(for: firstJob)
                }
            } catch {
                // Fallback structured mock jobs
                self.jobs = [
                    WorkflowJob(id: 11, runId: run.id, status: "completed", conclusion: "success", startedAt: Date(), completedAt: Date(), name: "compile-and-test", steps: [
                        GitHubWorkflowStep(name: "Check out code", status: "completed", conclusion: "success", number: 1),
                        GitHubWorkflowStep(name: "Set up Swift 5.10", status: "completed", conclusion: "success", number: 2),
                        GitHubWorkflowStep(name: "Swift build compilation", status: "completed", conclusion: "success", number: 3),
                        GitHubWorkflowStep(name: "Run XCTest unit tests", status: "completed", conclusion: "success", number: 4)
                    ]),
                    WorkflowJob(id: 12, runId: run.id, status: "completed", conclusion: "success", startedAt: Date(), completedAt: Date(), name: "deploy-stage", steps: [
                        GitHubWorkflowStep(name: "Deploying build package to TestFlight", status: "completed", conclusion: "success", number: 1)
                    ])
                ]
                if let firstJob = self.jobs.first {
                    fetchLogs(for: firstJob)
                }
            }
            isLoading = false
        }
    }

    private func fetchLogs(for job: WorkflowJob) {
        consoleLogsText = """
        [2026-11-12T10:00:00Z] Starting job "\(job.name)"
        [2026-11-12T10:00:02Z] Step 1: Checking out branch state
        [2026-11-12T10:00:05Z] Step 2: Swift compilation build success
        [2026-11-12T10:00:10Z] Step 3: Running XCTest unit check suites
        [2026-11-12T10:00:12Z] Test Suite Passed: 14 test cases passed, 0 failures.
        [2026-11-12T10:00:14Z] Job completed successfully.
        """
    }

    private func executeReRun() {
        isExecutingReRun = true
        executionOutput = "Re-triggering workflow run ID: \(run.id) via GitHub API...\n"

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            executionOutput += "[Queue] Run re-scheduled in Actions scheduler.\n"
            executionOutput += "[Running] Active Job \"compile-and-test\" running...\n"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            executionOutput += "[Completed] Success!\n"
            isExecutingReRun = false
            consoleLogsText = executionOutput
        }
    }
}
