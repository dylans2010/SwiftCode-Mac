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

    // Selection states for bulk actions
    @State private var selectedIssueIDs: Set<Int> = []

    // Creation states
    @State private var newTitle = ""
    @State private var newBody = ""
    @State private var selectedLabel = "bug"
    @State private var selectedMilestone = "v1.0.0"
    @State private var selectedAssignee = "Jules"

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
            fetchIssues()
        }
        .onChange(of: context.displayMode) {
            fetchIssues()
        }
        .onChange(of: context.syncEventsCount) {
            fetchIssues()
        }
        .sheet(isPresented: $showCreateIssue) {
            createIssueSheet
        }
        .sheet(item: $selectedIssue) { issue in
            IssueDetailView(issue: issue)
        }
    }

    private var mainContent: some View {
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
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)

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
                .disabled(context.connectedRepository == nil)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isLoading {
                GitHubLoadingView(message: "Loading issues...")
            } else if issues.isEmpty {
                GitHubEmptyStateView(
                    title: "No Issues Open",
                    description: "No issues match your filter criteria. Create one now!",
                    systemImage: "exclamationmark.bubble",
                    accentColor: .cyan,
                    actionTitle: "Create Issue"
                ) {
                    showCreateIssue = true
                }
                .disabled(context.connectedRepository == nil)
            } else {
                let filtered = processedIssues

                if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchPattern)
                } else {
                    List {
                        Section("Repository Issue Register") {
                            ForEach(filtered) { issue in
                                Button {
                                    selectedIssue = issue
                                } label: {
                                    HStack(spacing: 16) {
                                        // Checkbox for bulk actions
                                        Button {
                                            if selectedIssueIDs.contains(issue.id) {
                                                selectedIssueIDs.remove(issue.id)
                                            } else {
                                                selectedIssueIDs.insert(issue.id)
                                            }
                                        } label: {
                                            Image(systemName: selectedIssueIDs.contains(issue.id) ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(selectedIssueIDs.contains(issue.id) ? .cyan : .secondary)
                                        }
                                        .buttonStyle(.plain)

                                        Image(systemName: issue.state == "open" ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                            .foregroundStyle(issue.state == "open" ? .cyan : .green)
                                            .font(.title3)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(issue.title)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.primary)

                                            HStack(spacing: 8) {
                                                Text("#\(issue.number)")
                                                    .font(.caption)
                                                    .bold()
                                                    .foregroundStyle(.secondary)

                                                Text("opened by \(issue.user.login) on \(issue.createdAt)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)

                                                // Metadata tags
                                                Text("bug")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.red.opacity(0.12))
                                                    .foregroundStyle(.red)
                                                    .cornerRadius(3)

                                                Text("v1.0.0")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.purple.opacity(0.12))
                                                    .foregroundStyle(.purple)
                                                    .cornerRadius(3)
                                            }
                                        }

                                        Spacer()

                                        Text(issue.state.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(issue.state == "open" ? Color.cyan.opacity(0.12) : Color.green.opacity(0.12))
                                            .foregroundStyle(issue.state == "open" ? .cyan : .green)
                                            .cornerRadius(4)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }

                        // Bulk actions footer
                        if !selectedIssueIDs.isEmpty {
                            Section("Bulk Commands Panel") {
                                HStack {
                                    Text("\(selectedIssueIDs.count) issues selected")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Button {
                                        executeBulkClose()
                                    } label: {
                                        Label("Close Selected Issues", systemImage: "xmark.circle")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.cyan)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private var processedIssues: [GitHubIssue] {
        var list = issues
        if !searchPattern.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchPattern) ||
                ($0.body ?? "").localizedCaseInsensitiveContains(searchPattern)
            }
        }
        return list
    }

    private var disconnectedPlaceholder: some View {
        GitHubEmptyStateView(
            title: "No Repository Associated",
            description: "A GitHub repository must first be associated with this project to view and manage Issues.",
            systemImage: "exclamationmark.circle",
            accentColor: .orange,
            actionTitle: "Configure Repository Association"
        ) {
            RepositoryContext.shared.showingSetRepoSheet = true
        }
    }

    private var createIssueSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("New Issue Specification", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)
                Spacer()
                Button("Cancel") {
                    showCreateIssue = false
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Issue Title").font(.caption.bold())
                    TextField("Title", text: $newTitle)
                        .textFieldStyle(.roundedBorder)

                    Text("Labels").font(.caption.bold())
                    Picker("Labels", selection: $selectedLabel) {
                        Text("bug").tag("bug")
                        Text("enhancement").tag("enhancement")
                        Text("documentation").tag("documentation")
                    }
                    .pickerStyle(.segmented)

                    Text("Milestone").font(.caption.bold())
                    Picker("Milestone", selection: $selectedMilestone) {
                        Text("v1.0.0").tag("v1.0.0")
                        Text("v1.1.0").tag("v1.1.0")
                    }
                    .pickerStyle(.segmented)

                    Text("Assignee").font(.caption.bold())
                    TextField("Assignee", text: $selectedAssignee)
                        .textFieldStyle(.roundedBorder)

                    Text("Description").font(.caption.bold())
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
        .frame(width: 480, height: 520)
    }

    private func fetchIssues() {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        let urlStr: String
        if context.displayMode == .entireAccount {
            urlStr = "https://api.github.com/issues?filter=all&state=\(filterState)&per_page=30"
        } else if let (owner, repo) = ownerAndRepo {
            urlStr = "https://api.github.com/repos/\(owner)/\(repo)/issues?state=\(filterState)&per_page=30"
        } else {
            issues = []
            return
        }

        isLoading = true
        Task {
            do {
                guard let url = URL(string: urlStr) else { return }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                let decoded = try JSONDecoder().decode([GitHubIssue].self, from: data)
                self.issues = decoded.filter { !$0.htmlUrl.contains("/pull/") }
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
                    "body": newBody.trimmingCharacters(in: .whitespacesAndNewlines),
                    "labels": [selectedLabel],
                    "milestone": 1 // Mock milestone index
                ]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                let (_, _) = try await URLSession.shared.data(for: request)

                newTitle = ""
                newBody = ""
                showCreateIssue = false
                fetchIssues()
            } catch {
                errorMessage = "Failed to create: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func executeBulkClose() {
        guard let (owner, repo) = ownerAndRepo else { return }
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        isLoading = true
        let idsToClose = selectedIssueIDs
        Task {
            do {
                for issueID in idsToClose {
                    guard let issue = issues.first(where: { $0.id == issueID }) else { continue }
                    let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues/\(issue.number)")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "PATCH"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body: [String: Any] = ["state": "closed"]
                    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                    _ = try await URLSession.shared.data(for: request)
                }
                successMessage = "Successfully closed selected issues on GitHub!"
                showSuccess = true
                selectedIssueIDs.removeAll()
                fetchIssues()
            } catch {
                errorMessage = "Failed to bulk close: \(error.localizedDescription)"
                showError = true
            }
            isLoading = false
        }
    }
}
