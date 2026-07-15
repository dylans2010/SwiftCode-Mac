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

    // Filter states
    @State private var prFilterMode: PullRequestFilter = .open

    enum PullRequestFilter: String, CaseIterable, Identifiable {
        case open = "Open"
        case draft = "Drafts"
        case closed = "Closed"
        case merged = "Merged"
        case assigned = "Assigned Reviews"

        var id: String { rawValue }
    }

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
            fetchPRs()
        }
        .onChange(of: context.displayMode) {
            fetchPRs()
        }
        .onChange(of: context.syncEventsCount) {
            fetchPRs()
        }
        .sheet(isPresented: $showCreatePR) {
            if let repoStr = context.connectedRepository, !repoStr.isEmpty {
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

    private var mainContent: some View {
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
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)

                Picker("Status", selection: $prFilterMode) {
                    ForEach(PullRequestFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .controlSize(.small)
                .frame(width: 150)

                Button {
                    fetchPRs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isFetching)

                Button {
                    showCreatePR = true
                } label: {
                    Label("New Pull Request", systemImage: "arrow.triangle.pull")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(context.connectedRepository == nil)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Loading pull requests...")
            } else if pullRequests.isEmpty {
                GitHubEmptyStateView(
                    title: "No Pull Requests Found",
                    description: "No pull requests match the selected state filter.",
                    systemImage: "arrow.triangle.pull",
                    accentColor: .green,
                    actionTitle: "Create New PR"
                ) {
                    showCreatePR = true
                }
                .disabled(context.connectedRepository == nil)
            } else {
                let filtered = processedPRs

                if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchPattern)
                } else {
                    List(filtered) { pr in
                        Button {
                            selectedPR = pr
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "arrow.triangle.pull")
                                    .foregroundStyle(prStateColor(pr))
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pr.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 6) {
                                        Text("#\(pr.number)")
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(.secondary)

                                        Text("opened by \(pr.user.login) on \(pr.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    // Build Check status label
                                    Label("Passing", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(4)

                                    Text(pr.state.uppercased())
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(prStateColor(pr).opacity(0.12))
                                        .foregroundStyle(prStateColor(pr))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var processedPRs: [GitHubPullRequest] {
        var list = pullRequests

        // Filter Mode
        switch prFilterMode {
        case .open:
            list = list.filter { $0.state.lowercased() == "open" }
        case .draft:
            list = list.filter { $0.state.lowercased() == "open" && ($0.body?.contains("[draft]") ?? false) }
        case .closed:
            list = list.filter { $0.state.lowercased() == "closed" }
        case .merged:
            list = list.filter { $0.state.lowercased() == "closed" && ($0.body?.contains("merge") ?? true) }
        case .assigned:
            list = list.filter { $0.state.lowercased() == "open" } // reviews assigned list
        }

        // Search text
        if !searchPattern.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchPattern) ||
                ($0.body ?? "").localizedCaseInsensitiveContains(searchPattern)
            }
        }

        return list
    }

    private func prStateColor(_ pr: GitHubPullRequest) -> Color {
        if pr.state.lowercased() == "closed" {
            return .purple
        }
        return .green
    }

    private var disconnectedPlaceholder: some View {
        GitHubEmptyStateView(
            title: "No Repository Associated",
            description: "A GitHub repository must first be associated with this project to view and manage Pull Requests.",
            systemImage: "arrow.triangle.pull",
            accentColor: .orange,
            actionTitle: "Configure Repository Association"
        ) {
            RepositoryContext.shared.showingSetRepoSheet = true
        }
    }

    private func fetchPRs() {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        isFetching = true
        Task {
            do {
                let urlStr: String
                if context.displayMode == .entireAccount {
                    urlStr = "https://api.github.com/search/issues?q=is:pr+is:open"
                } else if let (owner, repo) = ownerAndRepo {
                    urlStr = "https://api.github.com/repos/\(owner)/\(repo)/pulls"
                } else {
                    pullRequests = []
                    isFetching = false
                    return
                }

                guard let url = URL(string: urlStr) else { return }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase

                if context.displayMode == .entireAccount {
                    struct SearchResponse: Decodable {
                        let items: [GitHubPullRequest]
                    }
                    let response = try decoder.decode(SearchResponse.self, from: data)
                    self.pullRequests = response.items
                } else {
                    self.pullRequests = try decoder.decode([GitHubPullRequest].self, from: data)
                }
            } catch {
                self.errorMessage = "Failed to list Pull Requests: \(error.localizedDescription)"
                self.showError = true
            }
            isFetching = false
        }
    }
}
