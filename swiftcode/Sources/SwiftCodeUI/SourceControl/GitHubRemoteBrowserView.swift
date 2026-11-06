import SwiftUI
import SwiftCodeAssistant
import SwiftCodeGitHub

/// The GitHub remote browser: issues, pull requests, branches,
/// commits, releases, activity, notifications, organizations and
/// the user's repositories for one `owner/repo`, over the real
/// api.github.com clients (`GitHubClient` plus the extended clients
/// in `SwiftCodeGitHub`).
///
/// This is the port of the remote half of Legacy's GitHub views
/// (`SwiftCode/Views/GitHub/IssuesView.swift`,
/// `PullRequestsView.swift`, `IssueDetailView.swift`,
/// `PullRequestDetailView.swift`, `ReleasesView.swift`,
/// `NotificationsView.swift`, `OrganizationsView.swift`,
/// `RepositoriesView.swift`, `RepositoryDetailView.swift`,
/// `ActivityFeedView.swift`, `Legacy/BranchManagementView.swift`,
/// `Legacy/CommitHistoryView.swift`, `Legacy/GitHubIssuesView.swift`,
/// `Legacy/PullRequestView.swift`, `Menu Bar/NSCreatePRView.swift`,
/// `Menu Bar/NSCreateRepositoryView.swift`, `RepositoryContext.swift`):
/// the same lists and actions, rebuilt in SwiftCode style (default
/// accent, no Legacy orange) on SwiftCode's clients. The local git half
/// of those views is not here — it already exists in SwiftCode's source
/// control UI (`SourceControlCoordinator`, `BranchHistoryController`,
/// `CommitController`).
///
/// The token comes from the secret store (`SecretAccount.githubToken`,
/// set in Settings > Accounts). Public repositories read without a
/// token at GitHub's unauthenticated rate limit; writes and private
/// data show an honest "sign in" state instead of fake content.
/// Hosting and menu wiring are on the integration list: this view is
/// presented with `NSHostingController`, as `SettingsPanes.swift`
/// already does for `PaywallView`.
@MainActor
struct GitHubRemoteBrowserView: View {
    @State private var model = GitHubRemoteBrowserModel()
    @AppStorage("swiftcode.githubBrowser.owner") private var owner = ""
    @AppStorage("swiftcode.githubBrowser.repo") private var repo = ""
    @State private var tab = GitHubRemoteTab.issues
    @State private var path: [GitHubRemoteRoute] = []
    @State private var showingNewIssue = false
    @State private var showingNewPullRequest = false
    @State private var showingNewRepository = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                repoPicker
                Divider()
                TabView(selection: $tab) {
                    issuesTab.tag(GitHubRemoteTab.issues)
                    pullRequestsTab.tag(GitHubRemoteTab.pullRequests)
                    branchesTab.tag(GitHubRemoteTab.branches)
                    commitsTab.tag(GitHubRemoteTab.commits)
                    releasesTab.tag(GitHubRemoteTab.releases)
                    activityTab.tag(GitHubRemoteTab.activity)
                    notificationsTab.tag(GitHubRemoteTab.notifications)
                    organizationsTab.tag(GitHubRemoteTab.organizations)
                    repositoriesTab.tag(GitHubRemoteTab.repositories)
                }
                .tabViewStyle(.automatic)
            }
            .navigationDestination(for: GitHubRemoteRoute.self) { route in
                switch route {
                case .issue(let number):
                    GitHubIssueDetailView(model: model, number: number)
                case .pullRequest(let number):
                    GitHubPullRequestDetailView(model: model, number: number)
                case .repository(let owner, let repo):
                    GitHubRepositoryDetailView(model: model, owner: owner, repo: repo)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    if tab == .issues {
                        Button("New Issue") { showingNewIssue = true }
                            .disabled(!model.hasRepo)
                    }
                    if tab == .pullRequests {
                        Button("New Pull Request") { showingNewPullRequest = true }
                            .disabled(!model.hasRepo)
                    }
                    if tab == .repositories {
                        Button("New Repository") { showingNewRepository = true }
                            .disabled(!model.tokenAvailable)
                    }
                    Button("Refresh") { Task { await model.load(tab: tab) } }
                }
            }
            .sheet(isPresented: $showingNewIssue) {
                GitHubNewIssueSheet(model: model)
            }
            .sheet(isPresented: $showingNewPullRequest) {
                GitHubNewPullRequestSheet(model: model)
            }
            .sheet(isPresented: $showingNewRepository) {
                GitHubNewRepositorySheet(model: model)
            }
            .task {
                model.owner = owner
                model.repo = repo
                model.refreshToken()
                await model.load(tab: tab)
            }
            .onChange(of: tab) { _, newTab in
                Task { await model.load(tab: newTab) }
            }
            .onChange(of: owner) { _, newValue in model.owner = newValue }
            .onChange(of: repo) { _, newValue in model.repo = newValue }
        }
    }

    private var repoPicker: some View {
        HStack(spacing: 8) {
            TextField("owner", text: $owner)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            Text("/")
            TextField("repository", text: $repo)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("Load") { Task { await model.load(tab: tab) } }
                .disabled(!model.hasRepo)
            Spacer()
            if model.tokenAvailable {
                Label("Signed in", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("Not signed in — public data only", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    private var issuesTab: some View {
        GitHubRemoteListTab(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isEmpty: model.issues.isEmpty,
            emptyTitle: model.hasRepo ? "No issues" : "Enter a repository above",
            emptyDescription: model.hasRepo ? "This repository has no open issues." : "Issues, pull requests, branches, commits, releases and activity all read from the repository named above."
        ) {
            ForEach(model.issues, id: \.number) { issue in
                NavigationLink(value: GitHubRemoteRoute.issue(number: issue.number)) {
                    GitHubIssueRow(issue: issue)
                }
            }
        }
        .tabItem { Label("Issues", systemImage: "circle.circle") }
    }

    private var pullRequestsTab: some View {
        GitHubRemoteListTab(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isEmpty: model.pullRequests.isEmpty,
            emptyTitle: model.hasRepo ? "No pull requests" : "Enter a repository above",
            emptyDescription: model.hasRepo ? "This repository has no open pull requests." : ""
        ) {
            ForEach(model.pullRequests, id: \.number) { pr in
                NavigationLink(value: GitHubRemoteRoute.pullRequest(number: pr.number)) {
                    GitHubPullRequestRow(pr: pr)
                }
            }
        }
        .tabItem { Label("Pull Requests", systemImage: "arrow.triangle.pull") }
    }

    private var branchesTab: some View {
        GitHubRemoteListTab(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isEmpty: model.branches.isEmpty,
            emptyTitle: model.hasRepo ? "No branches" : "Enter a repository above",
            emptyDescription: ""
        ) {
            ForEach(model.branches, id: \.name) { branch in
                HStack {
                    Label(branch.name, systemImage: "arrow.triangle.branch")
                    Spacer()
                    Text(String(branch.commitSha.prefix(7)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tabItem { Label("Branches", systemImage: "arrow.triangle.branch") }
    }

    private var commitsTab: some View {
        GitHubRemoteListTab(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isEmpty: model.commits.isEmpty,
            emptyTitle: model.hasRepo ? "No commits" : "Enter a repository above",
            emptyDescription: ""
        ) {
            ForEach(model.commits, id: \.sha) { commit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.message.components(separatedBy: .newlines).first ?? commit.message)
                        .lineLimit(2)
                    HStack {
                        Text(String(commit.sha.prefix(7)))
                        if let author = commit.authorName { Text(author) }
                        if let date = commit.authorDate { Text(date, style: .date) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .tabItem { Label("Commits", systemImage: "clock") }
    }

    private var releasesTab: some View {
        GitHubRemoteListTab(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isEmpty: model.releases.isEmpty,
            emptyTitle: model.hasRepo ? "No releases" : "Enter a repository above",
            emptyDescription: ""
        ) {
            ForEach(model.releases) { release in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(release.name ?? release.tagName)
                            .font(.headline)
                        if release.prerelease {
                            Text("Pre-release").font(.caption).foregroundStyle(.secondary)
                        }
                        if release.draft {
                            Text("Draft").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(release.tagName).font(.caption).foregroundStyle(.secondary)
                    if let body = release.body, !body.isEmpty {
                        Text(body).lineLimit(3).font(.body)
                    }
                    if let published = release.publishedAt {
                        Text(published, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tabItem { Label("Releases", systemImage: "tag") }
    }

    private var activityTab: some View {
        GitHubRemoteListTab(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isEmpty: model.events.isEmpty,
            emptyTitle: model.hasRepo ? "No recent activity" : "Enter a repository above",
            emptyDescription: ""
        ) {
            ForEach(model.events) { event in
                HStack {
                    Label(event.type, systemImage: "circle")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let actor = event.actorLogin { Text(actor).font(.caption) }
                        if let date = event.createdAt { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .tabItem { Label("Activity", systemImage: "list.bullet") }
    }

    private var notificationsTab: some View {
        GitHubRemoteListTab(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isEmpty: model.notifications.isEmpty,
            emptyTitle: model.tokenAvailable ? "No notifications" : "Sign in to see notifications",
            emptyDescription: model.tokenAvailable ? "" : "Notifications need a GitHub token. Add one in Settings > Accounts."
        ) {
            ForEach(model.notifications) { notification in
                Button {
                    Task { await model.markNotificationRead(notification) }
                } label: {
                    HStack {
                        Image(systemName: notification.unread ? "circle.fill" : "circle")
                            .font(.caption2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notification.subjectTitle)
                            Text("\(notification.repositoryFullName) · \(notification.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .tabItem { Label("Notifications", systemImage: "bell") }
    }

    private var organizationsTab: some View {
        GitHubRemoteListTab(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isEmpty: model.organizations.isEmpty,
            emptyTitle: model.tokenAvailable ? "No organizations" : "Sign in to see organizations",
            emptyDescription: model.tokenAvailable ? "" : "Organizations need a GitHub token. Add one in Settings > Accounts."
        ) {
            ForEach(model.organizations) { org in
                HStack {
                    Label(org.login, systemImage: "person.3")
                    Spacer()
                    if let description = org.description {
                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .tabItem { Label("Organizations", systemImage: "person.3") }
    }

    private var repositoriesTab: some View {
        GitHubRemoteListTab(
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isEmpty: model.userRepositories.isEmpty,
            emptyTitle: model.tokenAvailable ? "No repositories" : "Sign in to see your repositories",
            emptyDescription: model.tokenAvailable ? "" : "Your repositories need a GitHub token. Add one in Settings > Accounts."
        ) {
            ForEach(model.userRepositories) { repository in
                NavigationLink(value: GitHubRemoteRoute.repository(owner: repository.ownerLogin, repo: repository.name)) {
                    GitHubRepositoryRow(repository: repository)
                }
            }
        }
        .tabItem { Label("Repositories", systemImage: "folder") }
    }
}

enum GitHubRemoteTab: Hashable {
    case issues, pullRequests, branches, commits, releases, activity, notifications, organizations, repositories
}

enum GitHubRemoteRoute: Hashable {
    case issue(number: Int)
    case pullRequest(number: Int)
    case repository(owner: String, repo: String)
}

/// The browser's state. One model for every tab: each load reads
/// the token fresh from the secret store, so signing in (or out)
/// in Settings > Accounts takes effect on the next refresh without
/// relaunching.
@Observable
@MainActor
final class GitHubRemoteBrowserModel {
    var owner = ""
    var repo = ""
    var tokenAvailable = false
    var isLoading = false
    var errorMessage: String?

    var issues: [GitHubIssue] = []
    var pullRequests: [GitHubPullRequest] = []
    var branches: [GitHubBranch] = []
    var commits: [GitHubCommit] = []
    var releases: [GitHubRelease] = []
    var events: [GitHubRepositoryEvent] = []
    var notifications: [GitHubNotification] = []
    var organizations: [GitHubOrganization] = []
    var userRepositories: [GitHubRepository] = []

    var hasRepo: Bool { !owner.isEmpty && !repo.isEmpty }

    private var token: String? {
        let raw = CodingAssistantServices.shared.store.readString(SecretAccount.githubToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.flatMap { $0.isEmpty ? nil : $0 }
    }

    func refreshToken() {
        tokenAvailable = token != nil
    }

    private func gitHubClient() -> GitHubClient {
        let token = token
        return GitHubClient(tokenProvider: { token })
    }

    private func releaseClient() -> GitHubReleaseClient {
        let token = token
        return GitHubReleaseClient(tokenProvider: { token })
    }

    private func listsClient() -> GitHubRemoteListsClient {
        let token = token
        return GitHubRemoteListsClient(tokenProvider: { token })
    }

    private func commentsClient() -> GitHubIssueCommentClient {
        let token = token
        return GitHubIssueCommentClient(tokenProvider: { token })
    }

    func load(tab: GitHubRemoteTab) async {
        refreshToken()
        switch tab {
        case .issues: await loadIssues()
        case .pullRequests: await loadPullRequests()
        case .branches: await loadBranches()
        case .commits: await loadCommits()
        case .releases: await loadReleases()
        case .activity: await loadActivity()
        case .notifications: await loadNotifications()
        case .organizations: await loadOrganizations()
        case .repositories: await loadRepositories()
        }
    }

    func loadIssues() async {
        guard hasRepo else { issues = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            issues = try await gitHubClient().listIssues(owner: owner, repo: repo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPullRequests() async {
        guard hasRepo else { pullRequests = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            pullRequests = try await gitHubClient().listPullRequests(owner: owner, repo: repo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadBranches() async {
        guard hasRepo else { branches = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            branches = try await gitHubClient().listBranches(owner: owner, repo: repo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadCommits() async {
        guard hasRepo else { commits = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            commits = try await gitHubClient().listCommits(owner: owner, repo: repo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadReleases() async {
        guard hasRepo else { releases = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            releases = try await releaseClient().listReleases(owner: owner, repo: repo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadActivity() async {
        guard hasRepo else { events = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            events = try await listsClient().listRepositoryEvents(owner: owner, repo: repo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadNotifications() async {
        guard tokenAvailable else { notifications = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            notifications = try await listsClient().listNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadOrganizations() async {
        guard tokenAvailable else { organizations = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            organizations = try await listsClient().listOrganizations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRepositories() async {
        guard tokenAvailable else { userRepositories = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            userRepositories = try await listsClient().listUserRepositories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markNotificationRead(_ notification: GitHubNotification) async {
        do {
            try await listsClient().markNotificationRead(threadId: notification.id)
            notifications.removeAll { $0.id == notification.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchIssue(number: Int) async -> GitHubIssue? {
        guard hasRepo else { return nil }
        return try? await gitHubClient().getIssue(owner: owner, repo: repo, number: number)
    }

    func fetchIssueComments(number: Int) async -> [GitHubIssueComment] {
        guard hasRepo else { return [] }
        return (try? await commentsClient().listIssueComments(owner: owner, repo: repo, number: number)) ?? []
    }

    func postIssueComment(number: Int, body: String) async -> Bool {
        guard hasRepo else { return false }
        do {
            _ = try await commentsClient().createIssueComment(owner: owner, repo: repo, number: number, body: body)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func fetchPullRequest(number: Int) async -> GitHubPullRequest? {
        guard hasRepo else { return nil }
        return try? await gitHubClient().getPullRequest(owner: owner, repo: repo, number: number)
    }

    func fetchPullRequestFiles(number: Int) async -> [GitHubPullRequestFile] {
        guard hasRepo else { return [] }
        return (try? await gitHubClient().listPullRequestFiles(owner: owner, repo: repo, number: number)) ?? []
    }

    func fetchPullRequestReviews(number: Int) async -> [GitHubReview] {
        guard hasRepo else { return [] }
        return (try? await gitHubClient().listPullRequestReviews(owner: owner, repo: repo, number: number)) ?? []
    }

    func fetchRepository(owner: String, repo: String) async -> GitHubRepository? {
        return try? await gitHubClient().getRepository(owner: owner, repo: repo)
    }

    func createIssue(title: String, body: String) async -> Bool {
        guard hasRepo else { return false }
        do {
            _ = try await gitHubClient().createIssue(owner: owner, repo: repo, title: title, body: body)
            await loadIssues()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createPullRequest(title: String, body: String, head: String, base: String) async -> Bool {
        guard hasRepo else { return false }
        do {
            _ = try await gitHubClient().createPullRequest(owner: owner, repo: repo, title: title, body: body, head: head, base: base)
            await loadPullRequests()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createRepository(name: String, description: String?, isPrivate: Bool) async -> Bool {
        do {
            _ = try await listsClient().createRepository(name: name, description: description, isPrivate: isPrivate)
            await loadRepositories()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// A tab's list with the three states every remote list shares:
/// loading, error, and empty.
private struct GitHubRemoteListTab<Content: View>: View {
    var isLoading: Bool
    var errorMessage: String?
    var isEmpty: Bool
    var emptyTitle: String
    var emptyDescription: String
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("Could not load", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "circle")
                } description: {
                    Text(emptyDescription)
                }
            } else {
                List {
                    content
                }
            }
        }
    }
}

private struct GitHubIssueRow: View {
    var issue: GitHubIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("#\(issue.number)").font(.caption).foregroundStyle(.secondary)
                Text(issue.title).lineLimit(2)
            }
            HStack {
                Text(issue.state)
                Text(issue.userLogin)
                if !issue.labels.isEmpty {
                    Text(issue.labels.joined(separator: ", "))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct GitHubPullRequestRow: View {
    var pr: GitHubPullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("#\(pr.number)").font(.caption).foregroundStyle(.secondary)
                Text(pr.title).lineLimit(2)
                if pr.draft { Text("Draft").font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                Text(pr.state)
                Text("\(pr.headRef) → \(pr.baseRef)")
                Text(pr.userLogin)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct GitHubRepositoryRow: View {
    var repository: GitHubRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(repository.fullName)
            HStack {
                if repository.isPrivate { Text("Private") }
                if let language = repository.language { Text(language) }
                Text("★ \(repository.stargazersCount)")
                Text("⑂ \(repository.forksCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let description = repository.description, !description.isEmpty {
                Text(description).font(.caption).lineLimit(2)
            }
        }
    }
}

private struct GitHubIssueDetailView: View {
    var model: GitHubRemoteBrowserModel
    var number: Int
    @State private var issue: GitHubIssue?
    @State private var comments: [GitHubIssueComment] = []
    @State private var commentText = ""
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let issue {
                List {
                    Section {
                        Text(issue.title).font(.headline)
                        if let body = issue.body, !body.isEmpty {
                            Text(body)
                        }
                        HStack {
                            Text(issue.state)
                            Text(issue.userLogin)
                            if let created = issue.createdAt { Text(created, style: .date) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Section("Comments") {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(comment.userLogin).font(.caption).foregroundStyle(.secondary)
                                Text(comment.body)
                            }
                        }
                        HStack {
                            TextField("Add a comment", text: $commentText)
                            Button("Post") {
                                Task {
                                    if await model.postIssueComment(number: number, body: commentText) {
                                        commentText = ""
                                        comments = await model.fetchIssueComments(number: number)
                                    }
                                }
                            }
                            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Issue not found", systemImage: "circle.circle")
            }
        }
        .navigationTitle("Issue #\(number)")
        .task {
            issue = await model.fetchIssue(number: number)
            comments = await model.fetchIssueComments(number: number)
            isLoading = false
        }
    }
}

private struct GitHubPullRequestDetailView: View {
    var model: GitHubRemoteBrowserModel
    var number: Int
    @State private var pr: GitHubPullRequest?
    @State private var files: [GitHubPullRequestFile] = []
    @State private var reviews: [GitHubReview] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let pr {
                List {
                    Section {
                        Text(pr.title).font(.headline)
                        if let body = pr.body, !body.isEmpty {
                            Text(body)
                        }
                        HStack {
                            Text(pr.state)
                            Text("\(pr.headRef) → \(pr.baseRef)")
                            Text(pr.userLogin)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Section("Changed files") {
                        ForEach(files, id: \.filename) { file in
                            HStack {
                                Text(file.filename).lineLimit(1)
                                Spacer()
                                Text("+\(file.additions) −\(file.deletions)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Reviews") {
                        if reviews.isEmpty {
                            Text("No reviews yet.").foregroundStyle(.secondary)
                        }
                        ForEach(reviews) { review in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(review.userLogin)
                                    Text(review.state).font(.caption).foregroundStyle(.secondary)
                                }
                                if let body = review.body, !body.isEmpty {
                                    Text(body)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Pull request not found", systemImage: "arrow.triangle.pull")
            }
        }
        .navigationTitle("Pull Request #\(number)")
        .task {
            pr = await model.fetchPullRequest(number: number)
            files = await model.fetchPullRequestFiles(number: number)
            reviews = await model.fetchPullRequestReviews(number: number)
            isLoading = false
        }
    }
}

private struct GitHubRepositoryDetailView: View {
    var model: GitHubRemoteBrowserModel
    var owner: String
    var repo: String
    @State private var repository: GitHubRepository?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let repository {
                List {
                    Section {
                        Text(repository.fullName).font(.headline)
                        if let description = repository.description, !description.isEmpty {
                            Text(description)
                        }
                        HStack {
                            if repository.isPrivate { Text("Private") }
                            if let language = repository.language { Text(language) }
                            Text("★ \(repository.stargazersCount)")
                            Text("⑂ \(repository.forksCount)")
                            if let branch = repository.defaultBranch { Text(branch) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView("Repository not found", systemImage: "folder")
            }
        }
        .navigationTitle("\(owner)/\(repo)")
        .task {
            repository = await model.fetchRepository(owner: owner, repo: repo)
            isLoading = false
        }
    }
}

private struct GitHubNewIssueSheet: View {
    var model: GitHubRemoteBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body = ""

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextEditor(text: $body)
                .frame(minHeight: 120)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Issue") {
                    Task {
                        if await model.createIssue(title: title, body: body) {
                            dismiss()
                        }
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }
}

private struct GitHubNewPullRequestSheet: View {
    var model: GitHubRemoteBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body = ""
    @State private var head = ""
    @State private var base = "main"

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Head branch", text: $head)
            TextField("Base branch", text: $base)
            TextEditor(text: $body)
                .frame(minHeight: 100)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Pull Request") {
                    Task {
                        if await model.createPullRequest(title: title, body: body, head: head, base: base) {
                            dismiss()
                        }
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || head.isEmpty || base.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 380)
    }
}

private struct GitHubNewRepositorySheet: View {
    var model: GitHubRemoteBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Description", text: $description)
            Toggle("Private", isOn: $isPrivate)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Repository") {
                    Task {
                        if await model.createRepository(name: name, description: description.isEmpty ? nil : description, isPrivate: isPrivate) {
                            dismiss()
                        }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 280)
    }
}
