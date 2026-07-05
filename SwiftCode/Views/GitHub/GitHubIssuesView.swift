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
    @EnvironmentObject private var projectManager: ProjectManager
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
        guard let repo = projectManager.activeProject?.githubRepo else { return "" }
        return String(repo.split(separator: "/").first ?? "")
    }
    private var repoName: String {
        guard let repo = projectManager.activeProject?.githubRepo else { return "" }
        return String(repo.split(separator: "/").last ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading Issues…").tint(.cyan)
                } else if let error = errorMessage {
                    errorView(error)
                } else if issues.isEmpty {
                    emptyView
                } else {
                    issueList
                }
            }
            .navigationTitle("GitHub Issues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .sheet(isPresented: $showCreateIssue) {
                createIssueSheet
            }
            .sheet(item: $selectedIssue) { issue in
                IssueDetailView(issue: issue, owner: owner, repo: repoName)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if issues.isEmpty && !owner.isEmpty {
                await loadIssues()
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Picker("State", selection: $filterState) {
                Text("Open").tag("open")
                Text("Closed").tag("closed")
                Text("All").tag("all")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            .onChange(of: filterState) {
                filterTask?.cancel()
                filterTask = Task { await loadIssues() }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 12) {
                Button { Task { await loadIssues() } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(.cyan)
                }
                .disabled(isLoading || owner.isEmpty)

                Button { showCreateIssue = true } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.cyan)
                }
                .disabled(owner.isEmpty)
            }
        }
    }

    // MARK: - Issue List

    private var issueList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(issues) { issue in
                    issueRow(issue)
                        .onTapGesture { selectedIssue = issue }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func issueRow(_ issue: GitHubIssue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.isOpen ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(issue.isOpen ? .cyan : .green)
                .font(.callout)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(issue.title)
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("#\(issue.number)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    if let user = issue.user {
                        Text("By \(user.login)")
                            .font(.caption2)
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
                                    .background(Color(hex: label.color).opacity(0.3), in: Capsule())
                                    .foregroundStyle(Color(hex: label.color))
                            }
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
        .contentShape(Rectangle())
    }

    // MARK: - Empty / Error

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 44))
                .foregroundStyle(.cyan.opacity(0.6))
            Text(owner.isEmpty ? "No GitHub Repo Linked" : "No Issues Found")
                .font(.headline).foregroundStyle(.white)
            Text(owner.isEmpty
                 ? "Link a GitHub repository to view issues."
                 : "No \(filterState) issues in this repository.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if !owner.isEmpty {
                Button { showCreateIssue = true } label: {
                    Label("Create Issue", systemImage: "plus.circle.fill")
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.cyan.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.red.opacity(0.7))
            Text("Failed to Load Issues").font(.headline).foregroundStyle(.white)
            Text(msg).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button("Retry") { Task { await loadIssues() } }
                .buttonStyle(.borderedProminent).tint(.cyan)
        }
    }

    // MARK: - Create Issue Sheet

    private var createIssueSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Issue title", text: $newIssueTitle)
                    .font(.headline)
                    .padding(10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                Text("Description (Optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $newIssueBody)
                    .font(.callout)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                if isCreating {
                    ProgressView("Creating Issue…").tint(.cyan)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea())
            .navigationTitle("New Issue")
            .navigationBarTitleDisplayMode(.inline)
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
        .preferredColorScheme(.dark)
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
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        Image(systemName: issue.isOpen ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(issue.isOpen ? .cyan : .green)
                        Text(issue.title)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 8) {
                        Text("#\(issue.number)")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Text(issue.isOpen ? "Open" : "Closed")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(issue.isOpen ? Color.cyan.opacity(0.2) : Color.green.opacity(0.2), in: Capsule())
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
                                    .background(Color(hex: label.color).opacity(0.3), in: Capsule())
                                    .foregroundStyle(Color(hex: label.color))
                            }
                        }
                    }

                    Divider().opacity(0.3)

                    if let body = issue.body, !body.isEmpty {
                        Text("Description")
                            .font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(body).font(.body).foregroundStyle(.primary).textSelection(.enabled)
                    } else {
                        Text("No Description Provided.")
                            .font(.body).foregroundStyle(.secondary)
                    }

                    Divider().opacity(0.3)

                    if let url = URL(string: issue.htmlUrl) {
                        Link(destination: url) {
                            Label("View On GitHub", systemImage: "safari")
                                .font(.callout).foregroundStyle(.cyan)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea())
            .navigationTitle("Issue #\(issue.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Color Hex Extension
// init(hex:) is defined in GeneralSettingsView.swift
