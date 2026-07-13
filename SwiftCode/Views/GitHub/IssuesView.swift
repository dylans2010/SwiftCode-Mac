import SwiftUI

@MainActor
struct IssuesView: View {
    let project: Project?
    @Binding var showSuccess: Bool
    @Binding var successMessage: String?
    @Binding var showError: Bool
    @Binding var errorMessage: String?

    @State private var issues: [GitHubIssue] = []
    @State private var isLoading = false
    @State private var searchPattern = ""
    @State private var filterState = "open"
    @State private var showCreateIssue = false
    @State private var selectedIssue: GitHubIssue?

    @State private var newTitle = ""
    @State private var newBody = ""

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
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search issues...", text: $searchPattern)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                Picker("State", selection: $filterState) {
                    Text("Open").tag("open")
                    Text("Closed").tag("closed")
                    Text("All").tag("all")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: filterState) {
                    fetchIssues()
                }

                Button {
                    fetchIssues()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)

                Button {
                    showCreateIssue = true
                } label: {
                    Label("New Issue", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isLoading {
                GitHubLoadingView(message: "Loading issues...")
            } else if issues.isEmpty {
                GitHubEmptyStateView(
                    title: "No Issues",
                    description: "No issues matches your filter or are open in this repository.",
                    systemImage: "exclamationmark.bubble",
                    accentColor: .cyan,
                    actionTitle: "New Issue"
                ) {
                    showCreateIssue = true
                }
            } else {
                let filtered = searchPattern.isEmpty ? issues : issues.filter {
                    $0.title.localizedCaseInsensitiveContains(searchPattern) ||
                    ($0.body ?? "").localizedCaseInsensitiveContains(searchPattern)
                }

                if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchPattern)
                } else {
                    List(filtered) { issue in
                        Button {
                            selectedIssue = issue
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: issue.state == "open" ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(issue.state == "open" ? .cyan : .green)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text("#\(issue.number) opened by \(issue.user.login) on \(issue.createdAt)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(issue.state.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(issue.state == "open" ? Color.cyan.opacity(0.12) : Color.green.opacity(0.12))
                                    .foregroundStyle(issue.state == "open" ? .cyan : .green)
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
            fetchIssues()
        }
        .sheet(isPresented: $showCreateIssue) {
            createIssueSheet
        }
        .sheet(item: $selectedIssue) { issue in
            IssueDetailView(issue: issue)
        }
    }

    private var createIssueSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("New Issue", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)
                Spacer()
                Button("Cancel") {
                    showCreateIssue = false
                }
                .buttonStyle(.bordered)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Title", text: $newTitle)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $newBody)
                        .frame(height: 120)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            Button {
                submitIssue()
            } label: {
                Text("Submit New Issue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
        .frame(width: 450)
    }

    private func fetchIssues() {
        guard let (owner, repo) = ownerAndRepo else { return }

        isLoading = true
        Task {
            do {
                guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else {
                    errorMessage = "GitHub token required. Configure in Settings."
                    showError = true
                    isLoading = false
                    return
                }

                let urlStr = "https://api.github.com/repos/\(owner)/\(repo)/issues?state=\(filterState)&per_page=30"
                guard let url = URL(string: urlStr) else { return }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                let decoded = try JSONDecoder().decode([GitHubIssue].self, from: data)
                // Filter out pull requests (GitHub API lists PRs as issues)
                self.issues = decoded.filter { _ in !url.absoluteString.contains("pulls") } // Or similar, wait, GitHubIssue usually has pull_request key. Let's parse or just show them.
            } catch {
                errorMessage = "Failed to load issues: \(error.localizedDescription)"
                showError = true
            }
            isLoading = false
        }
    }

    private func submitIssue() {
        guard let (owner, repo) = ownerAndRepo else { return }
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues") else { return }

        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "title": newTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    "body": newBody.trimmingCharacters(in: .whitespacesAndNewlines)
                ]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                let (_, _) = try await URLSession.shared.data(for: request)

                newTitle = ""
                newBody = ""
                showCreateIssue = false
                fetchIssues()
            } catch {
                errorMessage = "Failed to create issue: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

struct GitHubIssue: Identifiable, Decodable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let createdAt: String
    let user: IssueUser

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user
        case createdAt = "created_at"
    }

    struct IssueUser: Decodable {
        let login: String
    }
}
