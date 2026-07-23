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
    @State private var showingWorkflowCreator = false

    private var context: RepositoryContext {
        RepositoryContext.shared
    }

    private var ownerAndRepo: (String, String)? {
        guard let repoStr = context.connectedRepository, !repoStr.isEmpty else { return nil }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    var body: some View {
        VStack(spacing: 0) {
            if context.displayMode == .connectedRepository && context.connectedRepository == nil {
                disconnectedPlaceholder
            } else {
                mainContent
            }
        }
        .onAppear {
            fetchRuns()
        }
        .onChange(of: context.displayMode) {
            fetchRuns()
        }
        .onChange(of: context.syncEventsCount) {
            fetchRuns()
        }
        .sheet(isPresented: .init(get: { selectedRun != nil }, set: { if !$0 { selectedRun = nil } })) {
            if let run = selectedRun {
                WorkflowRunsView(run: run, project: project)
            }
        }
        .sheet(isPresented: $showingWorkflowCreator) {
            NavigationStack {
                WorkflowsCreateView(project: project)
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack(spacing: 12) {
                Label("GitHub Actions", systemImage: "play.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)

                Spacer()

                Button {
                    showingWorkflowCreator = true
                } label: {
                    Label("Create Visual Workflow", systemImage: "plus.circle.fill")
                }

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
                    description: "No GitHub Actions workflows have been executed yet.",
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
    }

    private var disconnectedPlaceholder: some View {
        GitHubEmptyStateView(
            title: "No Repository Associated",
            description: "A GitHub repository must first be associated with this project to view and manage Actions.",
            systemImage: "play.circle",
            accentColor: .orange,
            actionTitle: "Configure Repository Association"
        ) {
            RepositoryContext.shared.showingSetRepoSheet = true
        }
    }

    private func fetchRuns() {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        let urlStr: String
        if context.displayMode == .entireAccount {
            // Note: Since there is no simple global workflow runs API, we list user repositories and get workflow runs for the connected repo if any, or default to general.
            // Let's query notifications or repository workflow list, or if not possible, use the connected repo runs.
            if let (owner, repo) = ownerAndRepo {
                urlStr = "https://api.github.com/repos/\(owner)/\(repo)/actions/runs"
            } else {
                runs = []
                return
            }
        } else if let (owner, repo) = ownerAndRepo {
            urlStr = "https://api.github.com/repos/\(owner)/\(repo)/actions/runs"
        } else {
            runs = []
            return
        }

        isFetching = true
        Task {
            do {
                guard let url = URL(string: urlStr) else { return }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)

                struct RunsResponse: Decodable {
                    let workflowRuns: [WorkflowRunDetail]
                }

                struct WorkflowRunDetail: Decodable {
                    let id: Int
                    let name: String?
                    let runNumber: Int
                    let status: String
                    let conclusion: String?
                    let actor: ActorDetail?
                    let createdAt: String
                }

                struct ActorDetail: Decodable {
                    let login: String
                }

                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(RunsResponse.self, from: data)

                self.runs = response.workflowRuns.map { r in
                    WorkflowRunSummary(
                        id: r.id,
                        name: r.name ?? "Workflow",
                        runNumber: r.runNumber,
                        status: r.status,
                        conclusion: r.conclusion,
                        actorLogin: r.actor?.login ?? "actor",
                        createdAt: r.createdAt
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
