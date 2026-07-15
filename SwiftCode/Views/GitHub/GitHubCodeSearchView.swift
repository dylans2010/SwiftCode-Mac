import SwiftUI
import AppKit

@MainActor
struct GitHubCodeSearchView: View {
    let project: Project?

    enum SearchMode: String, CaseIterable, Identifiable {
        case local = "Local Code Search"
        case discover = "GitHub Discover"

        var id: String { rawValue }
    }

    enum DiscoverType: String, CaseIterable, Identifiable {
        case repositories = "Repositories"
        case users = "Users"
        case code = "Code"
        case issues = "Issues & PRs"
        case topics = "Topics"

        var id: String { rawValue }
    }

    @State private var mode: SearchMode = .local

    // MARK: - Local Search State
    @State private var localQuery = ""
    @State private var localResults: [String] = []
    @State private var isLocalSearching = false

    // MARK: - GitHub Discover State
    @State private var discoverQuery = ""
    @State private var discoverType: DiscoverType = .repositories
    @State private var isDiscoverSearching = false
    @State private var discoverResults: [DiscoverResultItem] = []

    // Advanced Filters
    @State private var filterLanguage = ""
    @State private var filterLicense = ""
    @State private var filterStars = ""
    @State private var filterForks = ""
    @State private var filterSize = ""
    @State private var filterOrg = ""
    @State private var filterTopic = ""
    @State private var filterArchived = false
    @State private var filterVisibility = "all" // "all", "public", "private"

    // Sheet Selection for Browser
    @State private var selectedRepoFullName: String?

    var body: some View {
        VStack(spacing: 0) {
            // Mode Picker
            Picker("Search Mode", selection: $mode) {
                ForEach(SearchMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .frame(maxWidth: 400)

            Divider()

            switch mode {
            case .local:
                localSearchPane
            case .discover:
                discoverPane
            }
        }
        .sheet(item: Binding<RepoSelection?>(
            get: { selectedRepoFullName.map { RepoSelection(fullName: $0) } },
            set: { selectedRepoFullName = $0?.fullName }
        )) { selection in
            PublicRepositoryBrowserView(repoFullName: selection.fullName)
        }
    }

    // MARK: - Local Search Pane

    private var localSearchPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search local codebase content...", text: $localQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            performLocalSearch()
                        }
                }
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    performLocalSearch()
                } label: {
                    Text("Search")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isLocalSearching || localQuery.isEmpty)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isLocalSearching {
                GitHubLoadingView(message: "Searching codebase...")
            } else if localResults.isEmpty {
                GitHubEmptyStateView(
                    title: "Code Search",
                    description: "Search local codebase files for pattern matching or variable declarations.",
                    systemImage: "doc.text.magnifyingglass",
                    accentColor: .orange
                )
            } else {
                List(localResults, id: \.self) { result in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.orange)
                        Text(result)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func performLocalSearch() {
        guard let project = project else { return }
        isLocalSearching = true
        localResults.removeAll()

        Task {
            do {
                let fileManager = FileManager.default
                let dirURL = await project.directoryURL

                guard let enumerator = fileManager.enumerator(at: dirURL, includingPropertiesForKeys: nil) else {
                    isLocalSearching = false
                    return
                }

                var matched: [String] = []
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" || fileURL.pathExtension == "txt" || fileURL.pathExtension == "md" {
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        if content.contains(localQuery) {
                            let relPath = fileURL.path.replacingOccurrences(of: dirURL.path + "/", with: "")
                            matched.append(relPath)
                        }
                    }
                }
                self.localResults = matched
            } catch {
                // Silent catch
            }
            isLocalSearching = false
        }
    }

    // MARK: - GitHub Discover Pane

    private var discoverPane: some View {
        HSplitView {
            // Left Filters HUD
            VStack(alignment: .leading, spacing: 14) {
                Text("ADVANCED FILTERS")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                Group {
                    filterField(label: "Language", placeholder: "e.g. Swift", text: $filterLanguage)
                    filterField(label: "License", placeholder: "e.g. mit", text: $filterLicense)
                    filterField(label: "Min Stars", placeholder: "e.g. 500", text: $filterStars)
                    filterField(label: "Min Forks", placeholder: "e.g. 100", text: $filterForks)
                    filterField(label: "Min Size (KB)", placeholder: "e.g. 1000", text: $filterSize)
                    filterField(label: "Organization/Owner", placeholder: "e.g. apple", text: $filterOrg)
                    filterField(label: "Topic", placeholder: "e.g. swiftui", text: $filterTopic)
                }

                Toggle("Exclude Archived", isOn: Binding(
                    get: { !filterArchived },
                    set: { filterArchived = !$0 }
                ))
                .font(.caption)

                Picker("Visibility", selection: $filterVisibility) {
                    Text("All").tag("all")
                    Text("Public").tag("public")
                    Text("Private").tag("private")
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)

                Spacer()

                Button("Reset Filters") {
                    filterLanguage = ""
                    filterLicense = ""
                    filterStars = ""
                    filterForks = ""
                    filterSize = ""
                    filterOrg = ""
                    filterTopic = ""
                    filterArchived = false
                    filterVisibility = "all"
                    triggerDiscoverSearch()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding(14)
            .frame(width: 220)
            .background(Color(NSColor.windowBackgroundColor))

            // Right Search & Results
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("Search For", selection: $discoverType) {
                        ForEach(DiscoverType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .frame(width: 140)

                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search GitHub...", text: $discoverQuery)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                triggerDiscoverSearch()
                            }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    Button {
                        triggerDiscoverSearch()
                    } label: {
                        Text("Search")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isDiscoverSearching || discoverQuery.isEmpty)
                }
                .padding()
                .background(Color.secondary.opacity(0.03))

                Divider()

                if isDiscoverSearching {
                    GitHubLoadingView(message: "Searching GitHub...")
                } else if discoverResults.isEmpty {
                    GitHubEmptyStateView(
                        title: "Discover GitHub",
                        description: "Find repositories, users, or topics live from GitHub API.",
                        systemImage: "globe",
                        accentColor: .orange
                    )
                } else {
                    List(discoverResults) { item in
                        DiscoverResultRow(item: item) {
                            if discoverType == .repositories || discoverType == .code || discoverType == .issues {
                                selectedRepoFullName = item.repoFullName ?? item.title
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func filterField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onChange(of: text.wrappedValue) {
                    triggerDiscoverSearch()
                }
        }
    }

    private func triggerDiscoverSearch() {
        guard !discoverQuery.isEmpty else { return }

        // Build composite query: e.g. "myQuery + language:Swift + stars:>500"
        var queryParts = [discoverQuery]

        if !filterLanguage.isEmpty { queryParts.append("language:\(filterLanguage)") }
        if !filterLicense.isEmpty { queryParts.append("license:\(filterLicense)") }
        if !filterStars.isEmpty { queryParts.append("stars:>=\(filterStars)") }
        if !filterForks.isEmpty { queryParts.append("forks:>=\(filterForks)") }
        if !filterSize.isEmpty { queryParts.append("size:>=\(filterSize)") }
        if !filterOrg.isEmpty { queryParts.append("org:\(filterOrg)") }
        if !filterTopic.isEmpty { queryParts.append("topic:\(filterTopic)") }
        if filterArchived { queryParts.append("archived:true") }
        if filterVisibility == "public" { queryParts.append("is:public") }
        if filterVisibility == "private" { queryParts.append("is:private") }

        let compositeQuery = queryParts.joined(separator: " ")

        isDiscoverSearching = true
        Task {
            do {
                guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else {
                    isDiscoverSearching = false
                    return
                }

                let endpoint: String
                switch discoverType {
                case .repositories: endpoint = "repositories"
                case .users: endpoint = "users"
                case .code: endpoint = "code"
                case .issues: endpoint = "issues"
                case .topics: endpoint = "topics"
                }

                guard let encodedQuery = compositeQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "https://api.github.com/search/\(endpoint)?q=\(encodedQuery)") else {
                    isDiscoverSearching = false
                    return
                }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)

                // Decoders
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase

                switch discoverType {
                case .repositories:
                    struct RepoSearchResponse: Decodable {
                        let items: [RepoItem]
                        struct RepoItem: Decodable {
                            let id: Int
                            let name: String
                            let fullName: String
                            let description: String?
                            let stargazersCount: Int
                            let forksCount: Int
                            let language: String?
                        }
                    }
                    let res = try decoder.decode(RepoSearchResponse.self, from: data)
                    self.discoverResults = res.items.map { item in
                        DiscoverResultItem(
                            id: "\(item.id)",
                            title: item.fullName,
                            description: item.description ?? "No description",
                            subDetails: "★ \(item.stargazersCount)  ⑂ \(item.forksCount)  • \(item.language ?? "Unknown")",
                            repoFullName: item.fullName,
                            iconName: "folder.fill"
                        )
                    }

                case .users:
                    struct UserSearchResponse: Decodable {
                        let items: [UserItem]
                        struct UserItem: Decodable {
                            let id: Int
                            let login: String
                            let htmlUrl: String
                            let avatarUrl: String?
                        }
                    }
                    let res = try decoder.decode(UserSearchResponse.self, from: data)
                    self.discoverResults = res.items.map { item in
                        DiscoverResultItem(
                            id: "\(item.id)",
                            title: item.login,
                            description: item.htmlUrl,
                            subDetails: "Profile ID: \(item.id)",
                            repoFullName: nil,
                            iconName: "person.crop.circle.fill"
                        )
                    }

                case .code:
                    struct CodeSearchResponse: Decodable {
                        let items: [CodeItem]
                        struct CodeItem: Decodable {
                            let path: String
                            let repository: CodeRepo
                            struct CodeRepo: Decodable {
                                let fullName: String
                            }
                        }
                    }
                    let res = try decoder.decode(CodeSearchResponse.self, from: data)
                    self.discoverResults = res.items.enumerated().map { (index, item) in
                        DiscoverResultItem(
                            id: "\(index)",
                            title: (item.path as NSString).lastPathComponent,
                            description: item.path,
                            subDetails: "Repository: \(item.repository.fullName)",
                            repoFullName: item.repository.fullName,
                            iconName: "doc.text.fill"
                        )
                    }

                case .issues:
                    struct IssueSearchResponse: Decodable {
                        let items: [IssueItem]
                        struct IssueItem: Decodable {
                            let id: Int
                            let number: Int
                            let title: String
                            let state: String
                            let repositoryUrl: String
                        }
                    }
                    let res = try decoder.decode(IssueSearchResponse.self, from: data)
                    self.discoverResults = res.items.map { item in
                        let repoName = item.repositoryUrl.components(separatedBy: "/repos/").last ?? "Repository"
                        return DiscoverResultItem(
                            id: "\(item.id)",
                            title: "#\(item.number): \(item.title)",
                            description: "State: \(item.state.uppercased())",
                            subDetails: repoName,
                            repoFullName: repoName,
                            iconName: "exclamationmark.circle.fill"
                        )
                    }

                case .topics:
                    struct TopicSearchResponse: Decodable {
                        let items: [TopicItem]
                        struct TopicItem: Decodable {
                            let name: String
                            let shortDescription: String?
                            let released: String?
                        }
                    }
                    let res = try decoder.decode(TopicSearchResponse.self, from: data)
                    self.discoverResults = res.items.enumerated().map { (index, item) in
                        DiscoverResultItem(
                            id: "\(index)",
                            title: item.name,
                            description: item.shortDescription ?? "No description",
                            subDetails: "Released: \(item.released ?? "N/A")",
                            repoFullName: nil,
                            iconName: "tag.fill"
                        )
                    }
                }
            } catch {
                self.discoverResults = []
            }
            isDiscoverSearching = false
        }
    }
}

// MARK: - Helper Models

struct RepoSelection: Identifiable {
    var id: String { fullName }
    let fullName: String
}

struct DiscoverResultItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let subDetails: String
    let repoFullName: String?
    let iconName: String
}

struct DiscoverResultRow: View {
    let item: DiscoverResultItem
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.iconName)
                    .foregroundStyle(.orange)
                    .font(.title3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(item.subDetails)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if item.repoFullName != nil {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }
}

// ====================================================================
// PUBLIC REPOSITORY BROWSER SHEET
// ====================================================================
@MainActor
struct PublicRepositoryBrowserView: View {
    let repoFullName: String
    @Environment(\.dismiss) private var dismiss

    @State private var meta: GitHubRepoDetail?
    @State private var readmeContent = ""
    @State private var selectedBranch = "main"
    @State private var branches: [GitHubBranch] = []
    @State private var activeTab: BrowserTab = .overview

    // Files state
    @State private var fileTree: [GitHubTreeEntry] = []
    @State private var selectedFilePath = ""
    @State private var selectedFileContent = ""
    @State private var isLoadingFiles = false
    @State private var isDownloading = false

    // Actions state
    @State private var isStarred = false
    @State private var isWatching = false

    enum BrowserTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case files = "Source Tree"
        case commits = "Commits"
        case releases = "Releases"

        var id: String { rawValue }
    }

    private var ownerAndRepo: (String, String)? {
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repoFullName)
                        .font(.title3.bold())
                    if let meta {
                        HStack(spacing: 8) {
                            Label("★ \(meta.stargazersCount)", systemImage: "star.fill").foregroundStyle(.yellow)
                            Label("⑂ \(meta.forksCount)", systemImage: "arrow.triangle.branch").foregroundStyle(.secondary)
                            Text("Default: \(meta.defaultBranch ?? "main")").font(.caption2).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }

                Spacer()

                Picker("Section", selection: $activeTab) {
                    ForEach(BrowserTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Spacer()

                HStack(spacing: 10) {
                    Button(isStarred ? "Starred" : "Star") {
                        toggleStar()
                    }
                    .buttonStyle(.bordered)

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            switch activeTab {
            case .overview:
                overviewPane
            case .files:
                filesPane
            case .commits:
                commitsPane
            case .releases:
                releasesPane
            }
        }
        .frame(width: 900, height: 650)
        .onAppear {
            loadRepositoryInfo()
        }
    }

    // MARK: - Overview Pane

    private var overviewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Description and topics
                if let meta {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meta.description ?? "No description provided.")
                            .font(.body)

                        if let topics = meta.topics, !topics.isEmpty {
                            DiscoverHFlowLayout(spacing: 6) {
                                ForEach(topics, id: \.self) { topic in
                                    Text(topic)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12))
                                        .foregroundStyle(.orange)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(8)
                }

                // Repo Actions Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("REPOSITORY ACTIONS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            cloneRepo()
                        } label: {
                            Label("Clone", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            forkRepo()
                        } label: {
                            Label("Fork", systemImage: "arrow.branch")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            downloadZip()
                        } label: {
                            Label(isDownloading ? "Downloading..." : "Download ZIP", systemImage: "doc.zipper")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDownloading)

                        Button {
                            copyCloneURL(ssh: false)
                        } label: {
                            Label("Copy HTTPS URL", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            copyCloneURL(ssh: true)
                        } label: {
                            Label("Copy SSH URL", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // README Preview
                VStack(alignment: .leading, spacing: 10) {
                    Text("README.md")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    if readmeContent.isEmpty {
                        Text("No README.md resolved or loading...")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Text(readmeContent)
                            .font(.system(.body, design: .serif))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Files Pane (Live Source Browser)

    private var filesPane: some View {
        HSplitView {
            // Files Tree Navigation
            VStack(spacing: 0) {
                if isLoadingFiles {
                    ProgressView().controlSize(.small).padding()
                    Spacer()
                } else {
                    List(fileTree) { entry in
                        HStack {
                            Image(systemName: entry.type == "tree" ? "folder.fill" : "doc.text")
                                .foregroundStyle(entry.type == "tree" ? .orange : .secondary)
                            Text(entry.path)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if entry.type == "blob" {
                                loadFileContent(path: entry.path)
                            }
                        }
                    }
                }
            }
            .frame(width: 250)

            // Content Viewer
            VStack(alignment: .leading, spacing: 0) {
                if selectedFilePath.isEmpty {
                    ContentUnavailableView(
                        "No File Selected",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Choose a code or documentation file on the left to preview contents live.")
                    )
                } else {
                    Text(selectedFilePath)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))

                    Divider()

                    ScrollView {
                        // Support Image preview
                        let isImage = selectedFilePath.hasSuffix(".png") || selectedFilePath.hasSuffix(".jpg") || selectedFilePath.hasSuffix(".jpeg") || selectedFilePath.hasSuffix(".gif")

                        if isImage {
                            VStack {
                                Spacer()
                                Text("Image preview is not fully supported for live API assets inside text buffers.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            Text(selectedFileContent)
                                .font(.system(size: 11, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(Color.black.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Commits Pane

    private var commitsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("COMMIT HISTORY")
                    .font(.headline)
                    .foregroundStyle(.orange)

                LiveCommitsHistoryListView(repoFullName: repoFullName)
            }
            .padding()
        }
    }

    // MARK: - Releases Pane

    private var releasesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("RELEASES & DISTRIBUTIONS")
                    .font(.headline)
                    .foregroundStyle(.orange)

                LiveReleasesListView(repoFullName: repoFullName)
            }
            .padding()
        }
    }

    // MARK: - Actions Helpers

    private func loadRepositoryInfo() {
        guard let (owner, repo) = ownerAndRepo else { return }

        Task {
            do {
                let fetchedMeta = try await GitHubService.shared.validateAndFetchRepo(owner: owner, repo: repo)
                self.meta = fetchedMeta
                self.selectedBranch = fetchedMeta.defaultBranch ?? "main"

                // Load README
                if let readme = try? await GitHubService.shared.getFileContent(owner: owner, repo: repo, path: "README.md") {
                    self.readmeContent = readme
                }

                // Load Tree
                loadRepoTree()
            } catch {
                // silent failure
            }
        }
    }

    private func loadRepoTree() {
        guard let (owner, repo) = ownerAndRepo else { return }

        isLoadingFiles = true
        Task {
            do {
                let tree = try await GitHubService.shared.getRepoTree(owner: owner, repo: repo, branch: selectedBranch)
                self.fileTree = tree
            } catch {
                // keeps tree empty
            }
            isLoadingFiles = false
        }
    }

    private func loadFileContent(path: String) {
        guard let (owner, repo) = ownerAndRepo else { return }

        selectedFilePath = path
        selectedFileContent = "Loading file content..."
        Task {
            do {
                let content = try await GitHubService.shared.getFileContent(owner: owner, repo: repo, path: path)
                self.selectedFileContent = content
            } catch {
                self.selectedFileContent = "Failed to load: \(error.localizedDescription)"
            }
        }
    }

    private func cloneRepo() {
        guard let meta else { return }
        let alert = NSAlert()
        alert.messageText = "Clone Repository"
        alert.informativeText = "Use the Copy Clone URL actions and configure in the 'Local Workspace' settings sheet."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func forkRepo() {
        guard let (owner, repo) = ownerAndRepo else { return }
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/forks")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (_, response) = try await URLSession.shared.data(for: request)
                let alert = NSAlert()
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    alert.messageText = "Fork Succeeded"
                    alert.informativeText = "Successfully scheduled repository fork under your GitHub account."
                } else {
                    alert.messageText = "Fork Failed"
                    alert.informativeText = "GitHub returned status: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                }
                alert.addButton(withTitle: "OK")
                alert.runModal()
            } catch {
                // silent catch
            }
        }
    }

    private func downloadZip() {
        guard let (owner, repo) = ownerAndRepo else { return }

        isDownloading = true
        Task {
            do {
                let localZipURL = try await GitHubService.shared.downloadRepositoryZip(owner: owner, repo: repo, branch: selectedBranch)
                let alert = NSAlert()
                alert.messageText = "Download Complete"
                alert.informativeText = "Successfully saved archive zip at:\n\(localZipURL.path)"
                alert.addButton(withTitle: "OK")
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Download Failed"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            isDownloading = false
        }
    }

    private func copyCloneURL(ssh: Bool) {
        guard let meta else { return }
        let url = ssh ? (meta.sshUrl ?? "git@github.com:\(repoFullName).git") : meta.cloneUrl
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url, forType: .string)
    }

    private func toggleStar() {
        guard let (owner, repo) = ownerAndRepo else { return }
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        isStarred.toggle()
        Task {
            do {
                let url = URL(string: "https://api.github.com/user/starred/\(owner)/\(repo)")!
                var request = URLRequest(url: url)
                request.httpMethod = isStarred ? "PUT" : "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                _ = try await URLSession.shared.data(for: request)
            } catch {
                // fallback toggle
            }
        }
    }
}

// MARK: - Live Commits Subview

@MainActor
struct LiveCommitsHistoryListView: View {
    let repoFullName: String
    @State private var commits: [GitHubCommit] = []
    @State private var isLoading = false

    var body: some View {
        VStack {
            if isLoading {
                ProgressView().controlSize(.small)
            } else if commits.isEmpty {
                Text("No commits retrieved or loading...").foregroundStyle(.secondary).font(.caption)
            } else {
                VStack(spacing: 8) {
                    ForEach(commits) { commit in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commit.commit.message)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text("Authored by \(commit.commit.author?.name ?? "Developer")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(commit.sha.prefix(7))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .onAppear {
            loadCommits()
        }
    }

    private func loadCommits() {
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return }
        let owner = String(parts[0])
        let repo = String(parts[1])

        isLoading = true
        Task {
            do {
                let list = try await GitHubService.shared.listCommits(owner: owner, repo: repo)
                self.commits = list
            } catch {
                // keep list empty
            }
            isLoading = false
        }
    }
}

// MARK: - Live Releases Subview

@MainActor
struct LiveReleasesListView: View {
    let repoFullName: String
    @State private var releases: [GitHubReleaseInfo] = []
    @State private var isLoading = false

    var body: some View {
        VStack {
            if isLoading {
                ProgressView().controlSize(.small)
            } else if releases.isEmpty {
                Text("No releases published yet.").foregroundStyle(.secondary).font(.caption)
            } else {
                VStack(spacing: 8) {
                    ForEach(releases) { release in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(release.name ?? release.tagName)
                                    .font(.subheadline.bold())
                                Text("Tag: \(release.tagName) • Published on \(release.createdAt)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .onAppear {
            loadReleases()
        }
    }

    private func loadReleases() {
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return }
        let owner = String(parts[0])
        let repo = String(parts[1])

        isLoading = true
        Task {
            do {
                let token = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
                let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=10")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601
                self.releases = try decoder.decode([GitHubReleaseInfo].self, from: data)
            } catch {
                // keep list empty
            }
            isLoading = false
        }
    }
}

// MARK: - Simple HFlowLayout Helper (unique name to avoid redeclarations!)

struct DiscoverHFlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    struct LayoutInfo {
        let size: CGSize
        let bounds: CGRect
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += maxHeight + spacing
                maxHeight = 0
            }
            currentX += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }

        return CGSize(width: width, height: currentY + maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var maxHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += maxHeight + spacing
                maxHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
    }
}
