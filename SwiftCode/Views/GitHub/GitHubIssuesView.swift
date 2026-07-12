import SwiftUI

// MARK: - GitHub Issue Model

struct GitHubIssue: Identifiable, Decodable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let htmlUrl: String
    let createdAt: String
    let user: IssueUser?
    let labels: [IssueLabel]

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, labels, user
        case htmlUrl = "html_url"
        case createdAt = "created_at"
    }

    struct IssueUser: Decodable {
        let login: String
        let avatarUrl: String?
        enum CodingKeys: String, CodingKey {
            case login
            case avatarUrl = "avatar_url"
        }
    }

    struct IssueLabel: Identifiable, Decodable {
        let id: Int
        let name: String
        let color: String
    }

    var isOpen: Bool { state == "open" }
}

// MARK: - GitHub Issues View

struct GitHubIssuesView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @EnvironmentObject private var settings: AppSettings

    @State private var issues: [GitHubIssue] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filterState: String = "open"
    @State private var showCreateIssue = false
    @State private var selectedIssue: GitHubIssue?
    @State private var newIssueTitle = ""
    @State private var newIssueBody = ""
    @State private var isCreating = false
    @State private var filterTask: Task<Void, Never>?

    private var owner: String {
        guard let repo = sessionStore.activeProject?.githubRepo else { return "" }
        return String(repo.split(separator: "/").first ?? "")
    }
    private var repoName: String {
        guard let repo = sessionStore.activeProject?.githubRepo else { return "" }
        return String(repo.split(separator: "/").last ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Card 1: Issue Management Filters
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Issue Tracking Filters", systemImage: "line.3.horizontal.decrease.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            HStack(spacing: 16) {
                                Picker("State", selection: $filterState) {
                                    Text("Open Issues").tag("open")
                                    Text("Closed Issues").tag("closed")
                                    Text("All Issues").tag("all")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 320)
                                .onChange(of: filterState) {
                                    filterTask?.cancel()
                                    filterTask = Task { await loadIssues() }
                                }

                                Spacer()

                                Button { showCreateIssue = true } label: {
                                    Label("New Issue", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                                .disabled(owner.isEmpty)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Issues List
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Issues Directory", systemImage: "list.bullet")
                                    .font(.headline)
                                    .foregroundColor(.cyan)
                                Spacer()
                            }

                            if isLoading {
                                VStack {
                                    ProgressView()
                                    Text("Loading repository issues...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 200)
                            } else if let error = errorMessage {
                                errorView(error)
                            } else if issues.isEmpty {
                                emptyView
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(issues) { issue in
                                        Button {
                                            selectedIssue = issue
                                        } label: {
                                            issueRow(issue)
                                        }
                                        .buttonStyle(.plain)

                                        if issue.id != issues.last?.id {
                                            Divider().opacity(0.3)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .navigationTitle("GitHub Issues")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        // Dismiss handled by sheets parent
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await loadIssues() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading || owner.isEmpty)
                }
            }
            .sheet(isPresented: $showCreateIssue) {
                createIssueSheet
            }
            .sheet(item: $selectedIssue) { issue in
                IssueDetailView(issue: issue, owner: owner, repo: repoName)
            }
        }
        .task {
            if issues.isEmpty && !owner.isEmpty {
                await loadIssues()
            }
        }
    }

    private func issueRow(_ issue: GitHubIssue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.isOpen ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(issue.isOpen ? .cyan : .green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text(issue.title)
                    .font(.body.bold())
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("#\(issue.number)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    if let user = issue.user {
                        Text("By \(user.login)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(formattedDate(issue.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !issue.labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(issue.labels) { label in
                                Text(label.name)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: label.color).opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color(hex: label.color))
                            }
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty / Error

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 44))
                .foregroundStyle(.cyan.opacity(0.6))
            Text(owner.isEmpty ? "No GitHub Repo Linked" : "No Issues Found")
                .font(.headline)
            Text(owner.isEmpty
                 ? "Link a GitHub repository to view issues."
                 : "No \(filterState) issues in this repository.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.red.opacity(0.7))
            Text("Failed to Load Issues")
                .font(.headline)
            Text(msg)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadIssues() } }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    // MARK: - Create Issue Sheet

    private var createIssueSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Issue Specifications", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.cyan)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Title")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Issue title", text: $newIssueTitle)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Description")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $newIssueBody)
                                    .font(.callout)
                                    .frame(minHeight: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            }

                            if isCreating {
                                ProgressView("Creating Issue…").tint(.cyan)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("New Issue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateIssue = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await createIssue() } }
                        .disabled(newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
        }
    }

    // MARK: - Load Issues

    private func loadIssues() async {
        guard !owner.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken),
              !token.isEmpty else {
            errorMessage = "GitHub token not configured. Add it in Settings."
            return
        }

        let stateParam = filterState == "all" ? "all" : filterState
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repoName)/issues?state=\(stateParam)&per_page=30") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            issues = try decoder.decode([GitHubIssue].self, from: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Create Issue

    private func createIssue() async {
        guard !owner.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }

        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken),
              !token.isEmpty else {
            errorMessage = "GitHub token not configured."
            return
        }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repoName)/issues") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "title": newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "body": newIssueBody.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            newIssueTitle = ""
            newIssueBody = ""
            showCreateIssue = false
            await loadIssues()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        guard let date = formatter.date(from: isoString) else { return isoString }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Issue Detail View

struct IssueDetailView: View {
    let issue: GitHubIssue
    let owner: String
    let repo: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Card 1: Issue Specifications
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top) {
                                Label("Issue specifications", systemImage: issue.isOpen ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(issue.isOpen ? .cyan : .green)
                                Spacer()
                            }

                            Text(issue.title)
                                .font(.title3.bold())

                            HStack(spacing: 8) {
                                Text("#\(issue.number)")
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                Text(issue.isOpen ? "Open" : "Closed")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(issue.isOpen ? Color.cyan.opacity(0.15) : Color.green.opacity(0.15), in: Capsule())
                                    .foregroundStyle(issue.isOpen ? .cyan : .green)
                                if let user = issue.user {
                                    Text("by \(user.login)").font(.caption).foregroundStyle(.secondary)
                                }
                            }

                            if !issue.labels.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(issue.labels) { label in
                                        Text(label.name)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color(hex: label.color).opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color(hex: label.color))
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Description
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Description", systemImage: "doc.text.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            if let body = issue.body, !body.isEmpty {
                                Text(body).font(.body).textSelection(.enabled)
                            } else {
                                Text("No Description Provided.")
                                    .font(.body).foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: External View
                    if let url = URL(string: issue.htmlUrl) {
                        GroupBox {
                            Link(destination: url) {
                                Label("View Issue On GitHub Website", systemImage: "safari")
                                    .font(.callout)
                                    .foregroundColor(.cyan)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .navigationTitle("Issue #\(issue.number)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
