import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "RepositoryExplorer")

@MainActor
public struct RepositoryExplorerView: View {
    let gitViewModel: GitViewModel
    let project: Project

    // Sidebar navigation states
    @State private var selectedItem: ExplorerSectionItem = .overview
    @State private var searchText = ""
    @State private var favorites: Set<String> = ["Overview", "Source Files"]
    @State private var recentlyViewed: [ExplorerSectionItem] = [.overview]
    @State private var expandedSections: Set<String> = ["General", "Code", "Collaboration", "DevOps"]

    // File Browser state for Source Files view
    @State private var selectedFile: URL?
    @State private var fileContent: String = ""
    @State private var fileList: [URL] = []
    @State private var fileSearchText = ""

    // Analytics Mock State
    @State private var mockAnalyticsPeriod = "Last 30 Days"

    // Alert & Message states
    @State private var showSuccessAlert = false
    @State private var successAlertMessage = ""

    public init(gitViewModel: GitViewModel, project: Project) {
        self.gitViewModel = gitViewModel
        self.project = project
    }

    public enum ExplorerSectionItem: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case source = "Source Files"
        case branches = "Branches"
        case tags = "Tags"
        case releases = "Releases"
        case pullRequests = "Pull Requests"
        case issues = "Issues"
        case discussions = "Discussions"
        case milestones = "Milestones"
        case actions = "Actions & Workflows"
        case deployments = "Deployments"
        case webhooks = "Webhooks"
        case secrets = "Secrets & Variables"
        case contributors = "Contributors"
        case analytics = "Insights & Analytics"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .overview: return "info.circle"
            case .source: return "folder"
            case .branches: return "arrow.triangle.branch"
            case .tags: return "tag"
            case .releases: return "shippingbox"
            case .pullRequests: return "arrow.triangle.pull"
            case .issues: return "exclamationmark.bubble"
            case .discussions: return "bubble.left.and.bubble.right"
            case .milestones: return "flag"
            case .actions: return "play.circle"
            case .deployments: return "cloud"
            case .webhooks: return "link"
            case .secrets: return "lock"
            case .contributors: return "person.3"
            case .analytics: return "chart.bar"
            }
        }

        public var category: String {
            switch self {
            case .overview, .analytics, .contributors:
                return "General"
            case .source, .branches, .tags, .releases:
                return "Code"
            case .pullRequests, .issues, .discussions, .milestones:
                return "Collaboration"
            case .actions, .deployments, .webhooks, .secrets:
                return "DevOps"
            }
        }
    }

    public var body: some View {
        HSplitView {
            // Sidebar Navigation
            sidebarView
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 350)
                .layoutPriority(1)

            // Primary Detail Workspace
            detailWorkspaceView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(2)
        }
        .onAppear {
            loadFiles()
        }
    }

    // MARK: - Sidebar View

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Search & Repository Header
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "shippingbox.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.headline)
                            .lineLimit(1)
                        if let repo = project.githubRepo {
                            Text(repo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("No repository connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search explorer...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)

            Divider()

            // Sidebar List content
            List {
                // Favorites Section (if not empty)
                let favItems = ExplorerSectionItem.allCases.filter { favorites.contains($0.rawValue) }
                if !favItems.isEmpty {
                    Section(header: Text("Favorites").font(.caption).bold().foregroundStyle(.secondary)) {
                        ForEach(favItems) { item in
                            sidebarRow(for: item)
                        }
                    }
                }

                // Main Sections
                let categories = ["General", "Code", "Collaboration", "DevOps"]
                ForEach(categories, id: \.self) { category in
                    let isExpanded = expandedSections.contains(category)
                    Section(header:
                        HStack {
                            Text(category.uppercased())
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                if isExpanded {
                                    expandedSections.remove(category)
                                } else {
                                    expandedSections.insert(category)
                                }
                            } label: {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    ) {
                        if isExpanded {
                            let items = ExplorerSectionItem.allCases.filter {
                                $0.category == category &&
                                (searchText.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(searchText))
                            }
                            ForEach(items) { item in
                                sidebarRow(for: item)
                            }
                        }
                    }
                }

                // Recently Viewed Section
                if !recentlyViewed.isEmpty {
                    Section(header: Text("Recently Viewed").font(.caption).bold().foregroundStyle(.secondary)) {
                        ForEach(recentlyViewed, id: \.rawValue) { item in
                            sidebarRow(for: item)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func sidebarRow(for item: ExplorerSectionItem) -> some View {
        HStack {
            Label(item.rawValue, systemImage: item.icon)
                .font(.body)
                .foregroundStyle(selectedItem == item ? Color.accentColor : Color.primary)

            Spacer()

            // Favorite/Pin toggle
            Button {
                toggleFavorite(item)
            } label: {
                Image(systemName: favorites.contains(item.rawValue) ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(favorites.contains(item.rawValue) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(favorites.contains(item.rawValue) ? 1.0 : 0.0) // Show star only on hover / when favorited
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            selectItem(item)
        }
        .contextMenu {
            Button(favorites.contains(item.rawValue) ? "Unfavorite" : "Favorite") {
                toggleFavorite(item)
            }
            Button("Pin to Top") {
                toggleFavorite(item)
            }
        }
    }

    // MARK: - Navigation helpers

    private func toggleFavorite(_ item: ExplorerSectionItem) {
        if favorites.contains(item.rawValue) {
            favorites.remove(item.rawValue)
        } else {
            favorites.insert(item.rawValue)
        }
    }

    private func selectItem(_ item: ExplorerSectionItem) {
        selectedItem = item
        // Update Recently Viewed
        if let idx = recentlyViewed.firstIndex(of: item) {
            recentlyViewed.remove(at: idx)
        }
        recentlyViewed.insert(item, at: 0)
        if recentlyViewed.count > 5 {
            recentlyViewed.removeLast()
        }
    }

    // MARK: - Detail Workspace

    @ViewBuilder
    private var detailWorkspaceView: some View {
        VStack(spacing: 0) {
            // Inner Title/Toolbar Header
            HStack {
                Label(selectedItem.rawValue, systemImage: selectedItem.icon)
                    .font(.title2)
                    .bold()
                Spacer()
                if let repo = project.githubRepo {
                    Link(destination: URL(string: "https://github.com/\(repo)")!) { // safe inline string URL
                        Label("View on GitHub", systemImage: "safari")
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Workspace Panels Switcher
            switch selectedItem {
            case .overview:
                overviewDetailView
            case .source:
                sourceDetailView
            case .branches:
                BranchesView(gitViewModel: gitViewModel, project: project, showSuccess: .constant(false), successMessage: .constant(nil), showError: .constant(false), errorMessage: .constant(nil))
            case .tags:
                TagsView(project: project, showSuccess: .constant(false), successMessage: .constant(nil), showError: .constant(false), errorMessage: .constant(nil))
            case .releases:
                ReleasesView(project: project, showSuccess: .constant(false), successMessage: .constant(nil), showError: .constant(false), errorMessage: .constant(nil))
            case .pullRequests:
                PullRequestsView(project: project, showSuccess: .constant(false), successMessage: .constant(nil), showError: .constant(false), errorMessage: .constant(nil))
            case .issues:
                IssuesView(project: project, showSuccess: .constant(false), successMessage: .constant(nil), showError: .constant(false), errorMessage: .constant(nil))
            case .discussions:
                DiscussionsView(project: project)
            case .milestones:
                milestonesDetailView
            case .actions:
                ActionsView(project: project, showSuccess: .constant(false), successMessage: .constant(nil), showError: .constant(false), errorMessage: .constant(nil))
            case .deployments:
                deploymentsDetailView
            case .webhooks:
                webhooksDetailView
            case .secrets:
                secretsDetailView
            case .contributors:
                contributorsDetailView
            case .analytics:
                analyticsDetailView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Sub Panels

    private var overviewDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Info block
                VStack(alignment: .leading, spacing: 10) {
                    Text("Repository Specifications")
                        .font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        GridRow {
                            Text("Name:")
                                .bold()
                            Text(project.name)
                        }
                        GridRow {
                            Text("Directory:")
                                .bold()
                            Text(project.directoryURL.path)
                        }
                        if let repo = project.githubRepo {
                            GridRow {
                                Text("Remote Origin:")
                                    .bold()
                                Text("https://github.com/\(repo).git")
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }

                // Git status summary
                VStack(alignment: .leading, spacing: 10) {
                    Text("Git Status Summary")
                        .font(.headline)
                    if let status = gitViewModel.status {
                        HStack(spacing: 20) {
                            StatusCard(title: "Current Branch", value: status.branchName, icon: "arrow.triangle.branch", color: .purple)
                            StatusCard(title: "Unstaged Files", value: "\(status.unstagedFiles.count)", icon: "doc.badge.plus", color: .orange)
                            StatusCard(title: "Staged Files", value: "\(status.stagedFiles.count)", icon: "checkmark.circle", color: .green)
                        }
                    } else {
                        ContentUnavailableView("Status Unavailable", systemImage: "exclamationmark.triangle", description: Text("Run scan to load current branch information."))
                    }
                }

                // Recent Activity Timeline
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Project Commits")
                        .font(.headline)
                    if gitViewModel.history.isEmpty {
                        Text("No recent history loaded.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(gitViewModel.history.prefix(5), id: \.hash) { commit in
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(commit.message)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text("\(commit.author) committed on \(commit.date.formatted())")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(String(commit.hash.prefix(7)))
                                        .font(.system(.body, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.2))
                                        .cornerRadius(4)
                                }
                                Divider()
                            }
                        }
                        .padding()
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceDetailView: some View {
        HSplitView {
            // Source File list
            VStack(spacing: 0) {
                // Mini search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter files...", text: $fileSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .padding(8)

                Divider()

                List(fileList.filter { fileSearchText.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(fileSearchText) }, id: \.self) { url in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        loadFileContent(url)
                    }
                }
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)

            // Content viewer
            VStack(spacing: 0) {
                if let url = selectedFile {
                    HStack {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        Spacer()
                        Button("Reload") {
                            loadFileContent(url)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    ScrollView {
                        Text(fileContent)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                } else {
                    ContentUnavailableView("No File Selected", systemImage: "doc.text.magnifyingglass", description: Text("Select a source file on the left pane to explore its contents."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var milestonesDetailView: some View {
        List {
            MilestoneRow(title: "v1.0.0 Stable release", progress: 0.85, date: "Due by Nov 25, 2026", desc: "Production build validation, linter integration, and workflows dashboard.")
            MilestoneRow(title: "v1.1.0 Multi-window support", progress: 0.30, date: "Due by Jan 15, 2027", desc: "Incorporate drag and drop templates with custom visual CLI integrations.")
        }
    }

    private var deploymentsDetailView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Live Deployments")
                    .font(.headline)
                Spacer()
                Button("Trigger Manual Deploy") {
                    showSuccessAlert = true
                    successAlertMessage = "Deployment pipeline successfully triggered!"
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            List {
                DeploymentRow(environment: "Production", version: "v1.0.12", status: "Active", time: "2 hours ago", author: "DevOps Bot")
                DeploymentRow(environment: "Staging", version: "v1.1.0-alpha.3", status: "Active", time: "1 day ago", author: "Jules")
                DeploymentRow(environment: "Development", version: "feature-workflows", status: "Inactive", time: "3 days ago", author: "Jules")
            }
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK") {}
        } message: {
            Text(successAlertMessage)
        }
    }

    private var webhooksDetailView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Webhooks Configuration")
                    .font(.headline)
                Spacer()
                Button("Add Webhook") {}
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            List {
                WebhookRow(url: "https://api.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX", events: "Push, Pull Request, Commit Comment", active: true)
                WebhookRow(url: "https://discord.com/api/webhooks/1111111111111111111/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", events: "Issues, Discussions", active: true)
            }
        }
    }

    private var secretsDetailView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Encrypted Secrets & Environment Variables")
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Actions Secrets")
                            .font(.subheadline).bold()
                        SecretRow(name: "GITHUB_TOKEN", date: "Updated 3 days ago")
                        SecretRow(name: "SLACK_WEBHOOK_URL", date: "Updated 1 month ago")
                        SecretRow(name: "COCOAPODS_TRUNK_KEY", date: "Updated 2 weeks ago")
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Environment Variables")
                            .font(.subheadline).bold()
                        RepoVariableRow(name: "BUILD_CONFIGURATION", value: "Release")
                        RepoVariableRow(name: "FASTLANE_SCHEME", value: "SwiftCode")
                        RepoVariableRow(name: "SIMULATOR_DEVICE", value: "iPhone 16 Pro")
                    }
                }
                .padding(20)
            }
        }
    }

    private var contributorsDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Top Project Contributors")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 16) {
                    GridRow {
                        ContributorCard(name: "Jules", commits: 242, additions: "42,100", deletions: "12,400", role: "Lead Engineer")
                        ContributorCard(name: "DevOps Bot", commits: 154, additions: "5,400", deletions: "2,100", role: "CI Integrator")
                    }
                    GridRow {
                        ContributorCard(name: "Reviewer Prime", commits: 12, additions: "120", deletions: "340", role: "Core Code Reviewer")
                        ContributorCard(name: "Community Contrib", commits: 8, additions: "1,200", deletions: "900", role: "Doc Specialist")
                    }
                }
            }
            .padding(24)
        }
    }

    private var analyticsDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Productivity & Repo Insights")
                        .font(.headline)
                    Spacer()
                    Picker("Period", selection: $mockAnalyticsPeriod) {
                        Text("Last 7 Days").tag("Last 7 Days")
                        Text("Last 30 Days").tag("Last 30 Days")
                        Text("Last Year").tag("Last Year")
                    }
                    .frame(width: 150)
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Repository Velocity")
                        .font(.subheadline).bold()

                    HStack(spacing: 20) {
                        RepoMetricCard(title: "Commit frequency", value: "4.8 commits/day", subtitle: "+12% from last month", color: .green)
                        RepoMetricCard(title: "PR cycle time", value: "1.4 hours", subtitle: "Fastest 5% of similar repos", color: .purple)
                        RepoMetricCard(title: "Issue resolution", value: "92% complete", subtitle: "Avg 4.2 hours resolution", color: .blue)
                    }

                    Text("Code Distribution")
                        .font(.subheadline).bold()
                        .padding(.top, 10)

                    VStack(spacing: 12) {
                        LanguageProgressRow(language: "Swift", percentage: 94.2, color: .orange)
                        LanguageProgressRow(language: "Shell Script", percentage: 3.4, color: .green)
                        LanguageProgressRow(language: "Objective-C", percentage: 1.5, color: .indigo)
                        LanguageProgressRow(language: "Markdown/Documentation", percentage: 0.9, color: .teal)
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
            }
            .padding(24)
        }
    }

    // MARK: - File browser logic

    private func loadFiles() {
        let url = project.directoryURL
        do {
            let keys: [URLResourceKey] = [.isRegularFileKey]
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            var urls: [URL] = []
            var count = 0
            while let fileURL = enumerator?.nextObject() as? URL {
                // limit to prevent freezing on giant repos
                if count > 200 { break }

                let pathStr = fileURL.path
                if pathStr.contains("/.build") || pathStr.contains("/.git") || pathStr.contains("/DerivedData") || pathStr.contains("/node_modules") {
                    enumerator?.skipDescendants()
                    continue
                }

                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                if resourceValues.isRegularFile ?? false {
                    urls.append(fileURL)
                    count += 1
                }
            }
            fileList = urls
        } catch {
            logger.error("Error loading explorer files: \(error.localizedDescription)")
        }
    }

    private func loadFileContent(_ url: URL) {
        selectedFile = url
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            fileContent = "Failed to load file contents: \(error.localizedDescription)"
        }
    }
}

// MARK: - Helper Views

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 140)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct MilestoneRow: View {
    let title: String
    let progress: Double
    let date: String
    let desc: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(desc)
                .font(.body)
                .foregroundStyle(.secondary)

            ProgressView(value: progress) {
                HStack {
                    Text("\(Int(progress * 100))% Complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct DeploymentRow: View {
    let environment: String
    let version: String
    let status: String
    let time: String
    let author: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(environment)
                    .font(.headline)
                Text("\(version) • deployed by \(author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(status)
                    .bold()
                    .foregroundStyle(.green)
                Text(time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct WebhookRow: View {
    let url: String
    let events: String
    let active: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(url)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Text("Events: \(events)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(active ? "Active" : "Inactive")
                .foregroundStyle(active ? .green : .red)
                .bold()
        }
        .padding(.vertical, 6)
    }
}

struct SecretRow: View {
    let name: String
    let date: String

    var body: some View {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.body, design: .monospaced))
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove") {}
                .buttonStyle(.plain)
                .foregroundStyle(.red)
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

struct RepoVariableRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: "curlybraces")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.body, design: .monospaced))
                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit") {}
                .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

struct ContributorCard: View {
    let name: String
    let commits: Int
    let additions: String
    let deletions: String
    let role: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Commits:")
                        .bold()
                    Text("\(commits)")
                }
                GridRow {
                    Text("Additions:")
                        .bold()
                        .foregroundStyle(.green)
                    Text("+\(additions)")
                }
                GridRow {
                    Text("Deletions:")
                        .bold()
                        .foregroundStyle(.red)
                    Text("-\(deletions)")
                }
            }
        }
        .padding()
        .frame(width: 240)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct RepoMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .bold()
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 160, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct LanguageProgressRow: View {
    let language: String
    let percentage: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(language)
                    .bold()
                Spacer()
                Text(String(format: "%.1f%%", percentage))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: percentage, total: 100)
                .tint(color)
        }
    }
}
