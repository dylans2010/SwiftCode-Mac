import SwiftUI
import AppKit
import os.log
import YcodeIDECore
import YcodeAssistant
import SwiftCodeGitHub
import YcodeSubprocess

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "GitHubSettingsView")

@MainActor
struct GitHubSettingsView: View {
    let project: Project?

    @State private var token = ""
    @State private var gitName = ""
    @State private var gitEmail = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("GitHub & Git Workspace Settings")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Project Repository Association", systemImage: "link.badge.plus")
                                .font(.headline)
                                .foregroundStyle(.orange)

                            Text("Manage the GitHub remote connection and Git history for the currently opened project.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Divider()

                            SetRepoInProject()
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Personal Access Token (PAT)", systemImage: "key.fill")
                                .font(.headline)
                                .foregroundStyle(.green)

                            Text("Configure a secure GitHub Personal Access Token to authenticate API queries, fetch repository lists, create pull requests, and pull/push changes.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            SecureField("ghp_xxxxxxxxxxxx", text: $token)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 12) {
                                Button("Save Token") {
                                    saveToken()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Git Committer Identity", systemImage: "person.text.rectangle.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            Text("Identify yourself as the author of local commits. Git embeds these details into commit metadata records.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField("Full Name (e.g., Jane Doe)", text: $gitName)
                                .textFieldStyle(.roundedBorder)

                            TextField("Email Address (e.g., jane@example.com)", text: $gitEmail)
                                .textFieldStyle(.roundedBorder)

                            Button("Save Git Identity") {
                                saveIdentity()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Stop Source Control", systemImage: "xmark.octagon.fill")
                                .font(.headline)
                                .foregroundStyle(.red)

                            Text("Permanently disconnect remote GitHub mapping, erase credentials, and reset source control workspace settings. This takes you back to onboarding.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button(role: .destructive) {
                                stopSourceControl()
                            } label: {
                                Text("Stop Source Control")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .onAppear {
                token = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
                gitName = AppSettings.shared.gitUserName
                gitEmail = AppSettings.shared.gitUserEmail
            }
        }
    }

    private func saveToken() {
        KeychainService.shared.set(token, forKey: KeychainService.githubToken)
        AppSettings.shared.httpsAuthToken = token
        APIKeyManager.shared.storeKey(service: .gitHub, key: token)
    }

    private func saveIdentity() {
        AppSettings.shared.gitUserName = gitName
        AppSettings.shared.gitUserEmail = gitEmail
    }

    private func stopSourceControl() {
        let alert = NSAlert()
        alert.messageText = "Stop Source Control?"
        alert.informativeText = "Are you sure you want to permanently remove all git and source control configurations? This action will take you back to the Onboarding setup."
        alert.addButton(withTitle: "Stop and Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical

        if alert.runModal() == .alertFirstButtonReturn {
            AppSettings.shared.gitPath = ""
            AppSettings.shared.httpsAuthToken = ""
            AppSettings.shared.gitUserName = ""
            AppSettings.shared.gitUserEmail = ""
            AppSettings.shared.hasCompletedOnboarding = false

            KeychainService.shared.delete(forKey: KeychainService.githubToken)
            APIKeyManager.shared.deleteKey(service: .gitHub)
            if let proj = project {
                ProjectSessionStore.shared.updateProjectSettings(description: proj.description, githubRepo: nil, for: proj)
            }
        }
    }
}

@MainActor
struct SetRepoInProject: View {
    @Environment(ProjectSessionStore.self) private var sessionStore

    @State private var connectionTab = 0

    @State private var repoNameInput = ""
    @State private var userRepos: [GitHubRepository] = []
    @State private var isLoadingUserRepos = false
    @State private var selectedUserRepo = ""

    @State private var newRepoName = ""
    @State private var newRepoDescription = ""
    @State private var newRepoIsPrivate = false
    @State private var isCreatingRepo = false

    @State private var isPerformingAction = false
    @State private var statusMessage: String? = nil
    @State private var errorMessage: String? = nil

    @State private var cachedMetadata: GitHubRepository? = nil
    @State private var isLoadingMetadata = false

    private var currentProject: Project? {
        sessionStore.activeProject
    }

    private var connectedRepository: String? {
        guard let repoStr = currentProject?.githubRepo else { return nil }
        let trimmed = repoStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = trimmed
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "http://github.com/", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = cleaned.split(separator: "/")
        guard parts.count >= 2 else { return trimmed }
        let repo = String(parts[1]).replacingOccurrences(of: ".git", with: "")
        guard !repo.isEmpty else { return trimmed }
        return "\(parts[0])/\(repo)"
    }

    private var ownerAndRepo: (String, String)? {
        guard let repoStr = connectedRepository, !repoStr.isEmpty else { return nil }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private var isAuthenticated: Bool {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken) else { return false }
        return !token.isEmpty
    }

    private var isGitInitialized: Bool {
        guard let proj = currentProject else { return false }
        let gitDir = proj.directoryURL.appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let proj = currentProject {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: isGitInitialized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isGitInitialized ? .green : .orange)
                        Text(isGitInitialized ? "Local Git History Initialized" : "Local Git History Not Initialized")
                            .font(.subheadline.bold())

                        Spacer()

                        if !isGitInitialized {
                            Button("Initialize Local Git") {
                                initializeLocalGit()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(isPerformingAction)
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    if let connected = connectedRepository, !connected.isEmpty {
                        connectedRepoPanel(connected)
                    } else {
                        noConnectionPanel
                    }
                }
            } else {
                Text("No project is currently loaded in the workspace.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            if let msg = statusMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .padding(.top, 4)
            }

            if let err = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            fetchUserRepositories()
            if connectedRepository != nil && cachedMetadata == nil {
                Task {
                    await fetchMetadata()
                }
            }
        }
    }

    @ViewBuilder
    private func connectedRepoPanel(_ repoName: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Associated Repository")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(repoName)
                        .font(.title3.bold())
                }
                Spacer()
                Button("Disconnect Association", role: .destructive) {
                    disconnectRepository()
                }
                .buttonStyle(.bordered)
            }

            if isLoadingMetadata {
                ProgressView("Fetching remote metadata...").controlSize(.small)
            } else if let meta = cachedMetadata {
                Divider()

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Owner:").bold()
                        Text(repoName.split(separator: "/").first.map(String.init) ?? "Unknown")
                    }
                    GridRow {
                        Text("Remote URL:").bold()
                        Text(meta.cloneUrl ?? "")
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text("Default Branch:").bold()
                        Text(meta.defaultBranch ?? "main")
                    }
                    GridRow {
                        Text("Visibility:").bold()
                        Text(meta.isPrivate ? "Private" : "Public")
                            .foregroundStyle(meta.isPrivate ? .yellow : .green)
                    }
                    GridRow {
                        Text("Sync Status:").bold()
                        Text("Synchronized with active project")
                            .foregroundStyle(.green)
                    }
                }
                .font(.subheadline)
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    pushCurrentProject()
                } label: {
                    Label("Push Local Changes", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isPerformingAction)

                Button {
                    Task {
                        await fetchMetadata()
                    }
                } label: {
                    Label("Refresh Metadata", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingAction)
            }
        }
        .padding()
        .liquidGlass(style: .subtle, cornerRadius: 10)
    }

    private var noConnectionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Method", selection: $connectionTab) {
                Text("Connect Existing").tag(0)
                Text("Create New Repository").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            if connectionTab == 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select or enter a repository to link with this project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isLoadingUserRepos {
                        ProgressView().controlSize(.small)
                    } else if !userRepos.isEmpty {
                        Picker("Select Repository", selection: $selectedUserRepo) {
                            Text("-- Select a Repository --").tag("")
                            ForEach(userRepos) { repo in
                                Text(repo.fullName).tag(repo.fullName)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        TextField("Or enter manually: owner/repo", text: $repoNameInput)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()

                        Button("Connect") {
                            let name = selectedUserRepo.isEmpty ? repoNameInput.trimmingCharacters(in: .whitespacesAndNewlines) : selectedUserRepo
                            connectExistingRepository(name)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(repoNameInput.isEmpty && selectedUserRepo.isEmpty)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Configure and provision a new GitHub repository for this project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Repository Name", text: $newRepoName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Description (Optional)", text: $newRepoDescription)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Private Repository", isOn: $newRepoIsPrivate)
                        .toggleStyle(.checkbox)

                    Button("Create and Initialize Remote") {
                        createNewRepository()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(newRepoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingRepo)
                }
                .padding()
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }

    private func fetchUserRepositories() {
        guard isAuthenticated else { return }
        isLoadingUserRepos = true
        Task {
            do {
                let token = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
                userRepos = try await GitHubRemoteListsClient(tokenProvider: { token }).listUserRepositories()
            } catch {
            }
            isLoadingUserRepos = false
        }
    }

    private func fetchMetadata() async {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }
        guard let (owner, repo) = ownerAndRepo else { return }

        isLoadingMetadata = true
        do {
            cachedMetadata = try await GitHubClient(tokenProvider: { token }).getRepository(owner: owner, repo: repo)
        } catch {
            logger.warning("Failed to fetch repository metadata: \(error.localizedDescription)")
        }
        isLoadingMetadata = false
    }

    private func connectRepository(_ repoName: String) {
        guard let proj = currentProject else { return }
        ProjectSessionStore.shared.updateProjectSettings(description: proj.description, githubRepo: repoName, for: proj)
        Task {
            await fetchMetadata()
        }
    }

    private func disconnectRepository() {
        guard let proj = currentProject else { return }
        ProjectSessionStore.shared.updateProjectSettings(description: proj.description, githubRepo: nil, for: proj)
        cachedMetadata = nil
        statusMessage = "Repository association disconnected."
        errorMessage = nil
    }

    private func connectExistingRepository(_ repoName: String) {
        guard !repoName.isEmpty else { return }
        isPerformingAction = true
        statusMessage = "Connecting repository..."
        errorMessage = nil

        Task {
            do {
                connectRepository(repoName)
                try await configureLocalRemote(repoName: repoName)
                statusMessage = "Successfully connected project to \(repoName) and mapped local Git remote."
            } catch {
                errorMessage = "Mapped remote failed: \(error.localizedDescription)"
            }
            isPerformingAction = false
        }
    }

    private func createNewRepository() {
        let repoName = newRepoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoName.isEmpty else { return }

        isCreatingRepo = true
        statusMessage = "Creating remote GitHub repository..."
        errorMessage = nil

        Task {
            do {
                let token = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
                let created = try await GitHubRemoteListsClient(tokenProvider: { token }).createRepository(
                    name: repoName,
                    description: newRepoDescription,
                    isPrivate: newRepoIsPrivate
                )
                connectRepository(created.fullName)
                try await configureLocalRemote(repoName: created.fullName)
                statusMessage = "Successfully created and associated repository \(created.fullName)."
                newRepoName = ""
                newRepoDescription = ""
                fetchUserRepositories()
            } catch {
                errorMessage = "Repository creation failed: \(error.localizedDescription)"
            }
            isCreatingRepo = false
        }
    }

    private func initializeLocalGit() {
        guard let proj = currentProject else { return }
        isPerformingAction = true
        statusMessage = "Initializing local git..."
        errorMessage = nil

        Task {
            do {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                let dirURL = proj.directoryURL

                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["init"],
                    workingDirectory: dirURL
                )

                if result.exitCode == 0 {
                    statusMessage = "Local Git repository successfully initialized."
                    _ = try? await ProcessRunnerTool.shared.run(
                        executableURL: gitBinary,
                        arguments: ["config", "user.name", AppSettings.shared.gitUserName.isEmpty ? "SwiftCode" : AppSettings.shared.gitUserName],
                        workingDirectory: dirURL
                    )
                    _ = try? await ProcessRunnerTool.shared.run(
                        executableURL: gitBinary,
                        arguments: ["config", "user.email", AppSettings.shared.gitUserEmail.isEmpty ? "support@swiftcode.app" : AppSettings.shared.gitUserEmail],
                        workingDirectory: dirURL
                    )
                } else {
                    errorMessage = "Failed to initialize Git: \(result.stderr)"
                }
            } catch {
                errorMessage = "Git initialization failed: \(error.localizedDescription)"
            }
            isPerformingAction = false
        }
    }

    private func configureLocalRemote(repoName: String) async throws {
        guard let proj = currentProject else { return }
        let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
        let dirURL = proj.directoryURL

        if !isGitInitialized {
            _ = try? await ProcessRunnerTool.shared.run(executableURL: gitBinary, arguments: ["init"], workingDirectory: dirURL)
        }

        let token = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
        let authenticatedURL = "https://\(token)@github.com/\(repoName).git"

        _ = try? await ProcessRunnerTool.shared.run(executableURL: gitBinary, arguments: ["remote", "remove", "origin"], workingDirectory: dirURL)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: gitBinary,
            arguments: ["remote", "add", "origin", authenticatedURL],
            workingDirectory: dirURL
        )

        if result.exitCode != 0 {
            throw NSError(domain: "GitRemote", code: 1, userInfo: [NSLocalizedDescriptionKey: result.stderr])
        }
    }

    private func pushCurrentProject() {
        guard let proj = currentProject else { return }
        isPerformingAction = true
        statusMessage = "Staging and pushing changes to GitHub..."
        errorMessage = nil

        Task {
            do {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                let dirURL = proj.directoryURL

                _ = try? await ProcessRunnerTool.shared.run(executableURL: gitBinary, arguments: ["add", "."], workingDirectory: dirURL)
                _ = try? await ProcessRunnerTool.shared.run(executableURL: gitBinary, arguments: ["commit", "-m", "Sync current workspace changes via SwiftCode"], workingDirectory: dirURL)

                let branchResult = try await ProcessRunnerTool.shared.run(executableURL: gitBinary, arguments: ["rev-parse", "--abbrev-ref", "HEAD"], workingDirectory: dirURL)
                let activeBranch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let targetBranch = activeBranch.isEmpty ? "main" : activeBranch

                let pushResult = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["push", "-u", "origin", targetBranch],
                    workingDirectory: dirURL
                )

                if pushResult.exitCode == 0 {
                    statusMessage = "Successfully pushed all changes to branch '\(targetBranch)' on GitHub!"
                } else {
                    errorMessage = "Push failed: \(pushResult.stderr)"
                }
            } catch {
                errorMessage = "Push process failed: \(error.localizedDescription)"
            }
            isPerformingAction = false
        }
    }
}
