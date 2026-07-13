import SwiftUI

@MainActor
struct PullRequestsView: View {
    let project: Project?
    @Binding var showSuccess: Bool
    @Binding var successMessage: String?
    @Binding var showError: Bool
    @Binding var errorMessage: String?

    @State private var pullRequests: [GitHubPullRequest] = []
    @State private var isFetching = false
    @State private var searchPattern = ""
    @State private var showCreatePR = false
    @State private var selectedPR: GitHubPullRequest? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search pull requests...", text: $searchPattern)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    fetchPRs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isFetching)

                Button {
                    showCreatePR = true
                } label: {
                    Label("Create Pull Request", systemImage: "arrow.triangle.pull")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Loading pull requests...")
            } else if pullRequests.isEmpty {
                GitHubEmptyStateView(
                    title: "No Pull Requests",
                    description: "No pull requests open in this repository. Create one to share code changes.",
                    systemImage: "arrow.triangle.pull",
                    accentColor: .green,
                    actionTitle: "Create New PR"
                ) {
                    showCreatePR = true
                }
            } else {
                let filtered = searchPattern.isEmpty ? pullRequests : pullRequests.filter {
                    $0.title.localizedCaseInsensitiveContains(searchPattern) ||
                    ($0.body ?? "").localizedCaseInsensitiveContains(searchPattern)
                }

                if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchPattern)
                } else {
                    List(filtered) { pr in
                        Button {
                            selectedPR = pr
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "arrow.triangle.pull")
                                    .foregroundStyle(.green)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pr.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text("#\(pr.number) opened by \(pr.user.login) on \(pr.createdAt)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(pr.state.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundStyle(.green)
                                    .cornerRadius(4)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .onAppear {
            fetchPRs()
        }
        .sheet(isPresented: $showCreatePR) {
            if let repoStr = project?.githubRepo, !repoStr.isEmpty {
                let parts = repoStr.split(separator: "/")
                if parts.count == 2 {
                    PullRequestView(
                        owner: String(parts[0]),
                        repo: String(parts[1]),
                        currentBranch: "main"
                    )
                }
            } else {
                Text("No linked repository found to create PR.")
                    .padding()
            }
        }
        .sheet(item: $selectedPR) { pr in
            PullRequestDetailView(pr: pr)
        }
    }

    private func fetchPRs() {
        guard let repoStr = project?.githubRepo, !repoStr.isEmpty else { return }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else { return }

        isFetching = true
        Task {
            do {
                let prs = try await GitHubService.shared.listPullRequests(owner: String(parts[0]), repo: String(parts[1]))
                self.pullRequests = prs
            } catch {
                self.errorMessage = "Failed to list Pull Requests: \(error.localizedDescription)"
                self.showError = true
            }
            isFetching = false
        }
    }
}
