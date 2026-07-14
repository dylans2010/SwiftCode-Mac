import SwiftUI

typealias GitHubJob = WorkflowJob

@MainActor
struct WorkflowRunsView: View {
    let run: WorkflowRunSummary
    let project: Project?
    @Environment(\.dismiss) private var dismiss

    @State private var jobs: [GitHubJob] = []
    @State private var isLoading = false

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
                Label("Workflow Run Details", systemImage: "play.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title section
                    VStack(alignment: .leading, spacing: 10) {
                        Text(run.name)
                            .font(.title3.bold())

                        HStack(spacing: 8) {
                            Text("Run #\(run.runNumber)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Text(run.conclusion?.uppercased() ?? run.status.uppercased())
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(run.conclusion == "success" ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                                .foregroundStyle(run.conclusion == "success" ? .green : .orange)
                                .clipShape(Capsule())

                            Text("by \(run.actorLogin) on \(run.createdAt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    Divider()

                    // Jobs Panel
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Workflow Jobs", systemImage: "list.dash")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        if isLoading {
                            ProgressView()
                                .padding()
                        } else if jobs.isEmpty {
                            Text("No jobs found for this workflow run.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(jobs) { job in
                                    HStack {
                                        Image(systemName: job.conclusion == "success" ? "checkmark.circle.fill" : "play.circle.fill")
                                            .foregroundStyle(job.conclusion == "success" ? .green : .orange)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(job.name)
                                                .font(.subheadline.bold())
                                            Text(job.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text(job.status.uppercased())
                                            .font(.caption2.bold())
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 8)

                                    if job.id != jobs.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 24)
            }
        }
        .frame(width: 500, height: 480)
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
            } catch {
                // Silent catch
            }
            isLoading = false
        }
    }
}
