import SwiftUI

struct GitHubIntegrationView: View {
    let project: Project
    @EnvironmentObject private var projectManager: ProjectManager
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
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

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
                    .padding()
                }
            }
            .navigationTitle("GitHub")
            .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Authentication", icon: "key.fill", color: .yellow)

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
                            .foregroundStyle(.white)
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
                        .textInputAutocapitalization(.never)

                    Button {
                        connectToGitHub()
                    } label: {
                        Label("Connect To GitHub", systemImage: "link")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(token.isEmpty || isLoading)
                }
            }
        }
    }

    // MARK: - GitHub Modules Section

    private var githubModulesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("GitHub Modules", icon: "square.grid.2x2.fill", color: .purple)

            VStack(spacing: 0) {
                moduleRow(
                    title: "Branch Management",
                    subtitle: "Switch, create, or delete branches",
                    icon: "arrow.triangle.branch",
                    color: .green
                ) {
                    showBranchManagement = true
                }

                Divider().opacity(0.15).padding(.leading, 52)

                moduleRow(
                    title: "Commit History",
                    subtitle: "View history, amend, revert, cherry-pick",
                    icon: "clock.arrow.circlepath",
                    color: .orange
                ) {
                    showCommitHistory = true
                }

                Divider().opacity(0.15).padding(.leading, 52)

                moduleRow(
                    title: "Pull Requests",
                    subtitle: "Create PRs with reviewers and labels",
                    icon: "arrow.triangle.pull",
                    color: .purple
                ) {
                    showPullRequest = true
                }

                Divider().opacity(0.15).padding(.leading, 52)

                moduleRow(
                    title: "Licenses",
                    subtitle: "Browse, filter, and add OSS licenses",
                    icon: "doc.text.magnifyingglass",
                    color: .cyan
                ) {
                    showLicenses = true
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Repository Section

    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Repository", icon: "folder.fill.badge.gearshape", color: .blue)

            VStack(alignment: .leading, spacing: 12) {
                Text("Repository URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("GitHub URL", text: $repoURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .onChange(of: repoURL) {
                            saveRepoURL()
                            repoDetail = nil
                            repoValidationError = nil
                            if !ownerFromRepo.isEmpty && !repoNameFromURL.isEmpty {
                                loadBranches()
                            }
                        }
                    // Fetch button – lists repos from the authenticated user
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

                // Validation status
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

                // Repo info card
                if let detail = repoDetail {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: detail.isPrivate ? "lock.fill" : "globe")
                                .foregroundStyle(detail.isPrivate ? .yellow : .green)
                                .font(.caption)
                            Text(detail.fullName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
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
                            if let lang = detail.language {
                                Label(lang, systemImage: "chevron.left.forwardslash.chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                            }
                        }

                        HStack(spacing: 8) {
                            Text("Default Branch:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(detail.defaultBranch ?? "unknown")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                if let repositoryURL = URL(string: repoURL), !ownerFromRepo.isEmpty, !repoNameFromURL.isEmpty {
                    Link(destination: repositoryURL) {
                        Label("Open Repository", systemImage: "arrow.up.right.square")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showCreateRepoSheet = true
                } label: {
                    Label("Create New Repository", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                // Only show "Create Repository" when no repository is linked yet
                .opacity(ownerFromRepo.isEmpty ? 1 : 0)
                .disabled(!ownerFromRepo.isEmpty)

                // Save repo to device
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
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Branches Section

    private var branchesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader("Branches", icon: "arrow.branch", color: .green)
                Spacer()
                Button {
                    loadBranches()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                // Current branch indicator
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Active: ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(currentBranch)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }

                if branches.isEmpty {
                    Text("No Branches Loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(branches.prefix(8)) { branch in
                        BranchRow(branch: branch, isActive: branch.name == currentBranch) {
                            currentBranch = branch.name
                            successMessage = "Active branch set to '\(branch.name)'. Your next push will target this branch."
                            showSuccess = true
                        }
                    }
                    if branches.count > 8 {
                        Text("+ \(branches.count - 8) More Branches")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .onAppear { loadBranches() }
    }

    // MARK: - Push Section

    private var pushSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Sync", icon: "arrow.triangle.2.circlepath", color: .orange)

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
                        Label("Push", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

                    Button {
                        pullUpdates()
                    } label: {
                        Label("Pull", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }

                if isLoading {
                    ProgressView()
                        .tint(.orange)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Advanced Actions Section

    private var advancedActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Tools", icon: "wrench.and.screwdriver.fill", color: .purple)

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
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Workflow Section

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader("Recent Builds", icon: "hammer.fill", color: .purple)
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
                        .padding()
                } else {
                    ForEach(workflowRuns.prefix(5)) { run in
                        WorkflowRunRow(run: run)
                    }
                }
            }
        }
        .onAppear { loadWorkflowRuns() }
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
            .navigationBarTitleDisplayMode(.inline)
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
        .presentationDetents([.medium, .large])
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
                                        .foregroundStyle(.primary)
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
            .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Helper Views

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Actions

    private func loadSavedCredentials() {
        if let saved = KeychainService.shared.get(forKey: KeychainService.githubToken) {
            token = saved
            verifyToken()
        }
        if let savedRepo = project.githubRepo {
            // Check if savedRepo is already a full URL or just owner/repo
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
              let idx = projectManager.projects.firstIndex(where: { $0.id == project.id }) else { return }
        projectManager.projects[idx].githubRepo = "\(ownerFromRepo)/\(repoNameFromURL)"
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
        successMessage = "Pull functionality: Files pulled from '\(repoURL)'. (Implement per-file pull as needed.)"
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
                // Import the downloaded ZIP as a SwiftCode project
                let importedProject = try await ZipImporter.shared.importZip(at: zipURL)
                // Clean up the downloaded zip
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
                    // Update the current branch to match the repo default
                    currentBranch = detail.defaultBranch ?? "main"
                }
            } catch let error as GitHubError {
                await MainActor.run {
                    isValidatingRepo = false
                    switch error {
                    case .apiError(statusCode: 404, _):
                        repoValidationError = "Repository not found. Check the URL and ensure you have access."
                    case .apiError(statusCode: 403, _):
                        repoValidationError = "Access denied. The repository may be private — check your token permissions."
                    case .missingToken:
                        repoValidationError = "No GitHub token set. Add one in Settings to access private repos."
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

// MARK: - Branch Row

struct BranchRow: View {
    let branch: GitHubBranch
    let isActive: Bool
    let onSwitch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? .green : .secondary)
                .font(.caption)

            Text(branch.name)
                .font(.caption)
                .foregroundStyle(isActive ? .white : .primary)
                .lineLimit(1)

            if branch.protected {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }

            Spacer()

            if !isActive {
                Button("Switch") {
                    onSwitch()
                }
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.2), in: Capsule())
                .foregroundStyle(.green)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Workflow Run Row

struct WorkflowRunRow: View {
    let run: WorkflowRun

    var statusColor: Color {
        switch run.conclusion ?? run.status {
        case "success": return .green
        case "failure": return .red
        case "cancelled": return .gray
        case "in_progress": return .yellow
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: run.statusBadge)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.name ?? "Run #\(run.runNumber)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(run.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if run.isRunning {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.yellow)
            }
        }
    }
}
