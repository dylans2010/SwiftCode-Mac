import SwiftUI

@MainActor
struct ActionsView: View {
    let project: Project?
    @Binding var showSuccess: Bool
    @Binding var successMessage: String?
    @Binding var showError: Bool
    @Binding var errorMessage: String?

    @State private var runs: [WorkflowRunSummary] = []
    @State private var isFetching = false
    @State private var selectedRun: WorkflowRunSummary?

    private var ownerAndRepo: (String, String)? {
        guard let repoStr = project?.githubRepo, !repoStr.isEmpty else { return nil }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack(spacing: 12) {
                Label("GitHub Actions", systemImage: "play.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)

                Spacer()

                Button {
                    fetchRuns()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isFetching)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Loading workflow runs...")
            } else if runs.isEmpty {
                GitHubEmptyStateView(
                    title: "No Workflow Runs",
                    description: "No GitHub Actions workflows have been executed yet in this repository. Setup a .github/workflows YAML config.",
                    systemImage: "play.circle",
                    accentColor: .cyan
                )
            } else {
                List(runs) { run in
                    Button {
                        selectedRun = run
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: run.status == "completed" ? "checkmark.circle.fill" : "play.circle.fill")
                                .foregroundStyle(run.status == "completed" ? .green : .orange)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(run.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("Run #\(run.runNumber) by \(run.actorLogin) on \(run.createdAt)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(run.conclusion?.uppercased() ?? run.status.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(run.conclusion == "success" ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                                .foregroundStyle(run.conclusion == "success" ? .green : .orange)
                                .cornerRadius(4)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
        .onAppear {
            fetchRuns()
        }
        .sheet(item: $selectedRun) { run in
            WorkflowRunsView(run: run, project: project)
        }
    }

    private func fetchRuns() {
        guard let (owner, repo) = ownerAndRepo else { return }

        isFetching = true
        Task {
            do {
                let fetched = try await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repo)
                self.runs = fetched.map { r in
                    WorkflowRunSummary(
                        id: r.id,
                        name: r.name ?? "Workflow",
                        runNumber: r.runNumber,
                        status: r.status ?? "unknown",
                        conclusion: r.conclusion,
                        actorLogin: r.actor?.login ?? "actor",
                        createdAt: r.createdAt ?? ""
                    )
                }
            } catch {
                errorMessage = "Failed to load Actions runs: \(error.localizedDescription)"
                showError = true
            }
            isFetching = false
        }
    }
}

struct WorkflowRunSummary: Identifiable {
    let id: Int
    let name: String
    let runNumber: Int
    let status: String
    let conclusion: String?
    let actorLogin: String
    let createdAt: String
}
