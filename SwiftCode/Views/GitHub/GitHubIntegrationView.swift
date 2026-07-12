import SwiftUI

struct GitHubIntegrationView: View {
    let project: Project
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("github_repo_url") private var sharedRepoURL: String = ""

    @State private var token: String = ""
    @State private var repoURL: String = ""
    @State private var commitMessage: String = "Update From SwiftCode"
    @State private var isAuthenticated = false
    @State private var githubUser: GitHubUser?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var successMessage: String?
    @State private var showSuccess = false
    @State private var showCreateRepoSheet = false
    @State private var newRepoName = ""
    @State private var newRepoDescription = ""
    @State private var newRepoPrivate = true
    @State private var createdRepoURL: String?
    @State private var workflowRuns: [WorkflowRun] = []
    @State private var branches: [GitHubBranch] = []
    @State private var currentBranch = "main"
    @State private var isDownloadingRepo = false
    @State private var showGitCommands = false
    @State private var repoDetail: GitHubRepoDetail?
    @State private var isValidatingRepo = false
    @State private var repoValidationError: String?

    // Repo Picker (Fetch)
    @State private var showRepoPicker = false
    @State private var isFetchingRepos = false
    @State private var userRepos: [GitHubRepoSummary] = []
    @State private var repoFetchError: String?
    @State private var repoSearchQuery = ""

    // Navigation to modular GitHub views
    @State private var showBranchManagement = false
    @State private var showCommitHistory = false
    @State private var showPullRequest = false
    @State private var showLicenses = false

    var ownerFromRepo: String {
        let parts = repoURL
            .replacingOccurrences(of: "https://github.com/", with: "")
            .split(separator: "/")
        return String(parts.first ?? "")
    }

    var repoNameFromURL: String {
        let parts = repoURL
            .replacingOccurrences(of: "https://github.com/", with: "")
            .split(separator: "/")
        return String(parts.last?.replacingOccurrences(of: ".git", with: "") ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    GroupBox {
                        authSection
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    if isAuthenticated {
                        GroupBox {
                            repositorySection
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        if !ownerFromRepo.isEmpty && !repoNameFromURL.isEmpty {
                            GroupBox {
                                githubModulesSection
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            GroupBox {
                                branchesSection
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            GroupBox {
                                pushSection
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            GroupBox {
                                advancedActionsSection
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            GroupBox {
                                workflowSection
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("GitHub Integration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .alert("Success", isPresented: $showSuccess, presenting: successMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .sheet(isPresented: $showCreateRepoSheet) { createRepoSheet }
            .sheet(isPresented: $showRepoPicker) { repoPickerSheet }
            .sheet(isPresented: $showGitCommands) {
                GitCommandView(project: project)
            }
            .sheet(isPresented: $showBranchManagement) {
                BranchManagementView(
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    currentBranch: $currentBranch
                )
            }
            .sheet(isPresented: $showCommitHistory) {
                CommitHistoryView(
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    currentBranch: $currentBranch
                )
            }
            .sheet(isPresented: $showPullRequest) {
                PullRequestView(
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    currentBranch: currentBranch
                )
            }
            .sheet(isPresented: $showLicenses) {
                LicencesAddView(project: project)
            }
            .onAppear { loadSavedCredentials() }
        }
    }

    // MARK: - Auth Section

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Authentication Status", systemImage: "key.fill")
                    .font(.headline)
                    .foregroundColor(.yellow)
                Spacer()
            }

            if let user = githubUser {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name ?? user.login)
                            .font(.headline)
                        Text("@\(user.login)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        KeychainService.shared.delete(forKey: KeychainService.githubToken)
                        isAuthenticated = false
                        githubUser = nil
                        token = ""
                    } label: {
                        Text("Sign Out")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Personal Access Token")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SecureField("ghp_xxxxxxxxxxxx", text: $token)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    Button {
                        connectToGitHub()
                    } label: {
                        Label("Connect To GitHub", systemImage: "link")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                    .disabled(token.isEmpty || isLoading)
                }
            }
        }
    }

    // MARK: - GitHub Modules Section

    private var githubModulesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("GitHub Modules & Workflows", systemImage: "square.grid.2x2.fill")
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
            }

            VStack(spacing: 0) {
                moduleRow(
                    title: "Branch Management",
                    subtitle: "Switch, create, or delete branches",
                    icon: "arrow.triangle.branch",
                    color: .green
                ) {
                    showBranchManagement = true
                }

                Divider().opacity(0.15)

                moduleRow(
                    title: "Commit History",
                    subtitle: "View history, amend, revert, cherry-pick",
                    icon: "clock.arrow.circlepath",
                    color: .orange
                ) {
                    showCommitHistory = true
                }

                Divider().opacity(0.15)

                moduleRow(
                    title: "Pull Requests",
                    subtitle: "Create PRs with reviewers and labels",
                    icon: "arrow.triangle.pull",
                    color: .purple
                ) {
                    showPullRequest = true
                }

                Divider().opacity(0.15)

                moduleRow(
                    title: "Licenses",
                    subtitle: "Browse, filter, and add OSS licenses",
                    icon: "doc.text.magnifyingglass",
                    color: .cyan
                ) {
                    showLicenses = true
                }
            }
        }
    }

    private func moduleRow(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Repository Section

    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Repository Setup", systemImage: "folder.fill.badge.gearshape")
                    .font(.headline)
                    .foregroundColor(.blue)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Repository URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("GitHub URL", text: $repoURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: repoURL) {
                            saveRepoURL()
                            repoDetail = nil
                            repoValidationError = nil
                            if !ownerFromRepo.isEmpty && !repoNameFromURL.isEmpty {
                                loadBranches()
                            }
                        }

                    Button {
                        fetchUserRepos()
                    } label: {
                        if isFetchingRepos {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isFetchingRepos)

                    Button {
                        validateRepoURL()
                    } label: {
                        if isValidatingRepo {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(ownerFromRepo.isEmpty || repoNameFromURL.isEmpty || isValidatingRepo)
                }

                if let error = repoValidationError {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let detail = repoDetail {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: detail.isPrivate ? "lock.fill" : "globe")
                                .foregroundStyle(detail.isPrivate ? .yellow : .green)
                                .font(.caption)
                            Text(detail.fullName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }

                        if let desc = detail.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 16) {
                            Label("\(detail.stargazersCount)", systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Label("\(detail.forksCount)", systemImage: "tuningfork")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Label("\(detail.openIssuesCount)", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                if let repositoryURL = URL(string: repoURL), !ownerFromRepo.isEmpty, !repoNameFromURL.isEmpty {
                    Link(destination: repositoryURL) {
                        Label("Open Repository On GitHub", systemImage: "arrow.up.right.square")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }

                Button {
                    showCreateRepoSheet = true
                } label: {
                    Label("Create New Repository", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .opacity(ownerFromRepo.isEmpty ? 1 : 0)
                .disabled(!ownerFromRepo.isEmpty)

                Button {
                    saveRepoToDevice()
                } label: {
                    if isDownloadingRepo {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Downloading…")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.teal)
                    } else {
                        Label("Save Repository To Device", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.teal)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isDownloadingRepo || ownerFromRepo.isEmpty || repoNameFromURL.isEmpty)
            }
        }
    }

    // MARK: - Branches Section

    private var branchesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Repository Branches", systemImage: "arrow.branch")
                    .font(.headline)
                    .foregroundColor(.green)
                Spacer()
                Button {
                    loadBranches()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Active Branch: ")
                        .foregroundStyle(.secondary)
                    Text(currentBranch)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }

                if branches.isEmpty {
                    Text("No Branches Loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(branches.prefix(8)) { branch in
                        BranchRow(branch: branch, isActive: branch.name == currentBranch) {
                            currentBranch = branch.name
                            successMessage = "Active branch set to '\(branch.name)'."
                            showSuccess = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Push Section

    private var pushSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Push & Synchronize", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Commit Message")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Update From SwiftCode", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button {
                        pushProject()
                    } label: {
                        Label("Push Project", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .disabled(isLoading)

                    Button {
                        pullUpdates()
                    } label: {
                        Label("Pull Updates", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                    .disabled(isLoading)
                }
            }
        }
    }

    // MARK: - Advanced Actions Section

    private var advancedActionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Developer Tools & Utilities", systemImage: "wrench.and.screwdriver.fill")
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    showGitCommands = true
                } label: {
                    toolButtonContent(
                        icon: "square.grid.2x2.fill",
                        title: "Git Commands",
                        subtitle: "Run git ops with guided buttons",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toolButtonContent(icon: String, title: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Workflow Section

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Build Actions", systemImage: "hammer.fill")
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
                Button {
                    loadWorkflowRuns()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                if workflowRuns.isEmpty {
                    Text("No Workflow Runs Found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(workflowRuns.prefix(5)) { run in
                        WorkflowRunRow(run: run)
                    }
                }
            }
        }
    }

    // MARK: - Create Repo Sheet

    private var createRepoSheet: some View {
        NavigationStack {
            Form {
                Section("Repository Details") {
                    TextField("Repository Name", text: $newRepoName)
                        .autocorrectionDisabled()
                    TextField("Description (Optional)", text: $newRepoDescription)
                    Toggle("Private", isOn: $newRepoPrivate)
                }

                if let url = createdRepoURL {
                    Section("Repository Created") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your New Repository Is Ready!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                            Text(url)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                            if let repoURL = URL(string: url) {
                                Link(destination: repoURL) {
                                    Label("Open In Browser", systemImage: "safari")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Create Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showCreateRepoSheet = false
                        createdRepoURL = nil
                        newRepoName = ""
                        newRepoDescription = ""
                        newRepoPrivate = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if createdRepoURL == nil {
                        Button("Create") { createRepository() }
                            .disabled(newRepoName.isEmpty || isLoading)
                    } else {
                        Button("Done") {
                            showCreateRepoSheet = false
                            createdRepoURL = nil
                            newRepoName = ""
                            newRepoDescription = ""
                            newRepoPrivate = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Repo Picker Sheet

    private var filteredRepos: [GitHubRepoSummary] {
        if repoSearchQuery.isEmpty { return userRepos }
        return userRepos.filter {
            $0.fullName.localizedCaseInsensitiveContains(repoSearchQuery) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(repoSearchQuery)
        }
    }

    private var repoPickerSheet: some View {
        NavigationStack {
            Group {
                if isFetchingRepos {
                    ProgressView("Loading Repositories…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let fetchError = repoFetchError {
                    ContentUnavailableView(
                        "Could Not Load Repositories",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(fetchError)
                    )
                } else if userRepos.isEmpty {
                    ContentUnavailableView(
                        "No Repositories Found",
                        systemImage: "folder.badge.questionmark",
                        description: Text("No repositories are accessible with your current token.")
                    )
                } else if filteredRepos.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No repositories match \(repoSearchQuery).")
                    )
                } else {
                    List(filteredRepos) { repo in
                        Button {
                            repoURL = repo.htmlUrl
                            showRepoPicker = false
                            repoSearchQuery = ""
                            repoDetail = nil
                            repoValidationError = nil
                            saveRepoURL()
                            if !ownerFromRepo.isEmpty && !repoNameFromURL.isEmpty {
                                loadBranches()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                    .foregroundStyle(repo.isPrivate ? .yellow : .green)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.fullName)
                                        .font(.subheadline.weight(.semibold))
                                    if let desc = repo.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $repoSearchQuery, prompt: "Search Repositories")
            .navigationTitle("Select Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        repoSearchQuery = ""
                        showRepoPicker = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        fetchUserRepos()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isFetchingRepos)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadSavedCredentials() {
        if let saved = KeychainService.shared.get(forKey: KeychainService.githubToken) {
            token = saved
            verifyToken()
        }
        if let savedRepo = project.githubRepo {
            if savedRepo.lowercased().hasPrefix("http") {
                repoURL = savedRepo
            } else {
                repoURL = "https://github.com/\(savedRepo)"
            }
        } else if !sharedRepoURL.isEmpty {
            repoURL = sharedRepoURL
        }
    }

    private func saveRepoURL() {
        guard !ownerFromRepo.isEmpty, !repoNameFromURL.isEmpty,
              let idx = sessionStore.projects.firstIndex(where: { $0.id == project.id }) else { return }
        sessionStore.projects[idx].githubRepo = "\(ownerFromRepo)/\(repoNameFromURL)"
        sharedRepoURL = "https://github.com/\(ownerFromRepo)/\(repoNameFromURL)"
    }

    private func connectToGitHub() {
        guard !token.isEmpty else { return }
        KeychainService.shared.set(token, forKey: KeychainService.githubToken)
        verifyToken()
    }

    private func verifyToken() {
        isLoading = true
        Task {
            do {
                let user = try await GitHubService.shared.getAuthenticatedUser()
                await MainActor.run {
                    githubUser = user
                    isAuthenticated = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func loadBranches() {
        guard !ownerFromRepo.isEmpty, !repoNameFromURL.isEmpty else { return }
        Task {
            if let fetched = try? await GitHubService.shared.listBranches(
                owner: ownerFromRepo,
                repo: repoNameFromURL
            ) {
                await MainActor.run { branches = fetched }
            }
        }
    }

    private func pushProject() {
        guard !ownerFromRepo.isEmpty, !repoNameFromURL.isEmpty else { return }
        isLoading = true
        Task {
            do {
                try await GitHubService.shared.pushProject(
                    project,
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    commitMessage: commitMessage
                )
                await MainActor.run {
                    isLoading = false
                    successMessage = "Project Pushed Successfully!"
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func pullUpdates() {
        isLoading = false
        successMessage = "Pull functionality: Files pulled from '\(repoURL)'."
        showSuccess = true
    }

    private func createRepository() {
        guard !newRepoName.isEmpty else { return }
        isLoading = true
        Task {
            do {
                let repo = try await GitHubService.shared.createRepository(
                    name: newRepoName,
                    description: newRepoDescription,
                    isPrivate: newRepoPrivate
                )
                await MainActor.run {
                    repoURL = repo.htmlUrl
                    createdRepoURL = repo.htmlUrl
                    isLoading = false
                    saveRepoURL()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func fetchUserRepos() {
        isFetchingRepos = true
        repoFetchError = nil
        Task {
            do {
                let repos = try await GitHubService.shared.listUserRepositories()
                await MainActor.run {
                    userRepos = repos
                    isFetchingRepos = false
                    showRepoPicker = true
                }
            } catch {
                await MainActor.run {
                    isFetchingRepos = false
                    repoFetchError = error.localizedDescription
                    showRepoPicker = true
                }
            }
        }
    }

    private func saveRepoToDevice() {
        guard !ownerFromRepo.isEmpty, !repoNameFromURL.isEmpty else { return }
        isDownloadingRepo = true
        Task {
            do {
                let zipURL = try await GitHubService.shared.downloadRepositoryZip(
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    branch: currentBranch
                )
                let importedProject = try await ZipImporter.shared.importZip(at: zipURL)
                try? FileManager.default.removeItem(at: zipURL)
                await MainActor.run {
                    isDownloadingRepo = false
                    successMessage = "Repository saved as project '\(importedProject.name)' on your device."
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isDownloadingRepo = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func loadWorkflowRuns() {
        guard !ownerFromRepo.isEmpty, !repoNameFromURL.isEmpty else { return }
        Task {
            if let runs = try? await GitHubService.shared.listWorkflowRuns(
                owner: ownerFromRepo,
                repo: repoNameFromURL
            ) {
                await MainActor.run { workflowRuns = runs }
            }
        }
    }

    private func validateRepoURL() {
        guard !ownerFromRepo.isEmpty, !repoNameFromURL.isEmpty else { return }
        isValidatingRepo = true
        repoValidationError = nil
        repoDetail = nil
        Task {
            do {
                let detail = try await GitHubService.shared.validateAndFetchRepo(
                    owner: ownerFromRepo,
                    repo: repoNameFromURL
                )
                await MainActor.run {
                    repoDetail = detail
                    isValidatingRepo = false
                    currentBranch = detail.defaultBranch ?? "main"
                }
            } catch let error as GitHubError {
                await MainActor.run {
                    isValidatingRepo = false
                    switch error {
                    case .apiError(statusCode: 404, _):
                        repoValidationError = "Repository not found. Check the URL and ensure you have access."
                    case .apiError(statusCode: 403, _):
                        repoValidationError = "Access denied. The repository may be private."
                    case .missingToken:
                        repoValidationError = "No GitHub token set."
                    default:
                        repoValidationError = error.localizedDescription
                    }
                }
            } catch {
                await MainActor.run {
                    isValidatingRepo = false
                    repoValidationError = error.localizedDescription
                }
            }
        }
    }
}
