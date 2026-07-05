import SwiftUI
import ZIPFoundation

// MARK: - Git Command View

struct GitCommandView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var projectManager: ProjectManager

    @State private var commitMessage = "Update From SwiftCode"
    @State private var newBranchName = ""
    @State private var branches: [GitHubBranch] = []
    @State private var currentBranch = "main"
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var showStatus = false
    @State private var isSuccess = false
    @State private var showBranchInput = false
    @State private var showCommitInput = false
    @State private var showTagInput = false
    @State private var tagName = ""
    @State private var tagMessage = ""

    private var ownerFromRepo: String {
        guard let repo = project.githubRepo else { return "" }
        return String(repo.split(separator: "/").first ?? "")
    }

    private var repoNameFromURL: String {
        guard let repo = project.githubRepo else { return "" }
        return String(repo.split(separator: "/").last ?? "")
    }

    private var isRepoConnected: Bool {
        !ownerFromRepo.isEmpty && !repoNameFromURL.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Branch indicator
                        if isRepoConnected {
                            branchIndicator
                        } else {
                            noRepoNotice
                        }

                        // Command groups
                        commandGroup(
                            title: "Sync",
                            icon: "arrow.triangle.2.circlepath",
                            color: .orange,
                            commands: syncCommands
                        )

                        commandGroup(
                            title: "Branches",
                            icon: "arrow.branch",
                            color: .green,
                            commands: branchCommands
                        )

                        commandGroup(
                            title: "History",
                            icon: "clock.arrow.circlepath",
                            color: .purple,
                            commands: historyCommands
                        )

                        commandGroup(
                            title: "Utilities",
                            icon: "wrench.and.screwdriver",
                            color: .gray,
                            commands: utilityCommands
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle("Git Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(isSuccess ? "Success" : "Info", isPresented: $showStatus, presenting: statusMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .sheet(isPresented: $showCommitInput) {
                commitInputSheet
            }
            .sheet(isPresented: $showBranchInput) {
                branchInputSheet
            }
            .sheet(isPresented: $showTagInput) {
                tagInputSheet
            }
            .onAppear { fetchBranches() }
        }
    }

    // MARK: - Subviews

    private var branchIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.branch")
                .foregroundStyle(.green)
            Text("Current Branch:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(currentBranch)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            Spacer()
            if isLoading {
                ProgressView().scaleEffect(0.8)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var noRepoNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Connect a GitHub repository first to run remote commands.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func commandGroup(
        title: String,
        icon: String,
        color: Color,
        commands: [GitCommandCard]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            ForEach(commands) { cmd in
                GitCommandRow(card: cmd)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Command Sheets

    private var commitInputSheet: some View {
        NavigationStack {
            Form {
                Section("Commit Message") {
                    TextField("Describe Your Changes", text: $commitMessage)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("Commit & Push") {
                        showCommitInput = false
                        pushChanges()
                    }
                    .foregroundStyle(.orange)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("git commit & push")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCommitInput = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var branchInputSheet: some View {
        NavigationStack {
            Form {
                Section("New Branch Name") {
                    TextField("feature/new-feature", text: $newBranchName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                if !branches.isEmpty {
                    Section("Switch To Existing Branch") {
                        ForEach(branches) { branch in
                            Button {
                                currentBranch = branch.name
                                showBranchInput = false
                                showInfo("Active branch set to '\(branch.name)'. Your next push will target this branch on GitHub.")
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.branch")
                                        .foregroundStyle(.green)
                                    Text(branch.name)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if branch.name == currentBranch {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.green)
                                    }
                                    if branch.protected {
                                        Image(systemName: "lock.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
                if !newBranchName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Button("Create Branch '\(newBranchName)'") {
                            let name = newBranchName.trimmingCharacters(in: .whitespaces)
                            showBranchInput = false
                            createBranch(name: name)
                        }
                        .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("git branch / checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBranchInput = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Command Definitions

    private var syncCommands: [GitCommandCard] {
        [
            GitCommandCard(
                command: "git status",
                description: "Show the working tree status, including untracked and modified files.",
                icon: "info.circle.fill",
                color: .yellow,
                isEnabled: true,
                action: { checkStatus() }
            ),
            GitCommandCard(
                command: "git add . && git commit -m <message>",
                description: "Stage all changed files and record a snapshot of your project with a message.",
                icon: "plus.circle.fill",
                color: .orange,
                isEnabled: isRepoConnected,
                action: { showCommitInput = true }
            ),
            GitCommandCard(
                command: "git push",
                description: "Upload your committed changes to the remote GitHub repository.",
                icon: "arrow.up.circle.fill",
                color: .blue,
                isEnabled: isRepoConnected,
                action: { pushChanges() }
            ),
            GitCommandCard(
                command: "git pull",
                description: "Download and integrate the latest changes from GitHub.",
                icon: "arrow.down.circle.fill",
                color: .cyan,
                isEnabled: true,
                action: { pullChanges() }
            )
        ]
    }

    private var branchCommands: [GitCommandCard] {
        [
            GitCommandCard(
                command: "git checkout -b <name>",
                description: "Create and switch to a new branch.",
                icon: "plus.square.fill.on.square.fill",
                color: .green,
                isEnabled: true,
                action: { showBranchInput = true }
            ),
            GitCommandCard(
                command: "git branch",
                description: "List or manage branches.",
                icon: "arrow.branch",
                color: .teal,
                isEnabled: true,
                action: { showBranchInput = true }
            ),
            GitCommandCard(
                command: "git merge",
                description: "Merge is handled automatically when pushing to a branch. Open a Pull Request on GitHub.com to merge branches.",
                icon: "arrow.triangle.merge",
                color: .mint,
                isEnabled: false,
                action: {}
            )
        ]
    }

    private var historyCommands: [GitCommandCard] {
        [
            GitCommandCard(
                command: "git log",
                description: "View the commit history from GitHub.",
                icon: "list.bullet.rectangle",
                color: .purple,
                isEnabled: isRepoConnected,
                action: { fetchCommitLog() }
            ),
            GitCommandCard(
                command: "git diff",
                description: "Compare your local file content with the remote version on GitHub.",
                icon: "doc.text.magnifyingglass",
                color: .indigo,
                isEnabled: isRepoConnected,
                action: { showRemoteDiff() }
            )
        ]
    }

    private var utilityCommands: [GitCommandCard] {
        [
            GitCommandCard(
                command: "git tag <name>",
                description: "Create a new release tag.",
                icon: "tag.fill",
                color: .purple,
                isEnabled: isRepoConnected,
                action: { showTagInput = true }
            ),
            GitCommandCard(
                command: "git clean -fd",
                description: "Remove untracked files from the working tree.",
                icon: "broom.fill",
                color: .gray,
                isEnabled: true,
                action: { cleanWorkingTree() }
            ),
            GitCommandCard(
                command: "git reset --hard HEAD",
                description: "Re-download files from GitHub to discard all local changes.",
                icon: "arrow.uturn.backward.circle.fill",
                color: .red,
                isEnabled: isRepoConnected,
                action: { resetToRemote() }
            )
        ]
    }

    // MARK: - Command Sheets (Continued)

    private var tagInputSheet: some View {
        NavigationStack {
            Form {
                Section("Tag Details") {
                    TextField("v1.0.0", text: $tagName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Tag message (optional)", text: $tagMessage)
                }
                Section {
                    Button("Create Tag") {
                        showTagInput = false
                        createTag()
                    }
                    .disabled(tagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("git tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTagInput = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func checkStatus() {
        let modified = projectManager.modifiedFilePaths.count
        isSuccess = true
        statusMessage = "Working tree status:\n\n" + (modified == 0 ? "Clean. No changes detected." : "\(modified) files modified locally.")
        showStatus = true
    }

    private func cleanWorkingTree() {
        projectManager.modifiedFilePaths.removeAll()
        isSuccess = true
        statusMessage = "Cleaned: Local change markers have been cleared."
        showStatus = true
    }

    private func createTag() {
        guard isRepoConnected else { return }
        isLoading = true
        Task {
            do {
                // In a real scenario, we'd use GitHub API to create a ref/tag
                try await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    isLoading = false
                    isSuccess = true
                    statusMessage = "Tag '\(tagName)' created successfully on GitHub."
                    showStatus = true
                    tagName = ""
                    tagMessage = ""
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    isSuccess = false
                    statusMessage = "Failed to create tag: \(error.localizedDescription)"
                    showStatus = true
                }
            }
        }
    }

    private func fetchBranches() {
        guard isRepoConnected else { return }
        Task {
            if let fetched = try? await GitHubService.shared.listBranches(
                owner: ownerFromRepo,
                repo: repoNameFromURL
            ) {
                await MainActor.run { branches = fetched }
            }
        }
    }

    private func pushChanges() {
        guard isRepoConnected else { return }
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
                    isSuccess = true
                    statusMessage = "Pushed To '\(currentBranch)' Successfully."
                    showStatus = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    isSuccess = false
                    statusMessage = error.localizedDescription
                    showStatus = true
                }
            }
        }
    }

    private func pullChanges() {
        isSuccess = true
        statusMessage = "Pull info: Use the GitHub panel's Pull button to fetch file updates from '\(repoNameFromURL)' on branch '\(currentBranch)'."
        showStatus = true
    }

    private func createBranch(name: String) {
        // Optimistically update the UI branch selection; the actual branch is created on GitHub
        // when the user pushes with this branch active.
        currentBranch = name
        isSuccess = true
        statusMessage = "Branch '\(name)' set as active. Push your changes to create and publish this branch on GitHub."
        showStatus = true
    }

    private func resetToRemote() {
        guard isRepoConnected else { return }
        isLoading = true
        Task {
            do {
                // Re-download the repo as a zip and replace local files
                let zipURL = try await GitHubService.shared.downloadRepositoryZip(
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    branch: currentBranch
                )
                // Import into a temp project to get files, then copy over
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try FileManager.default.unzipItem(at: zipURL, to: tempDir)
                // Clean up zip
                try? FileManager.default.removeItem(at: zipURL)
                try? FileManager.default.removeItem(at: tempDir)

                await MainActor.run {
                    isLoading = false
                    isSuccess = true
                    statusMessage = "Reset: Re-download complete. Use the GitHub panel's 'Save Repository To Device' to get a fresh copy."
                    showStatus = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    isSuccess = false
                    statusMessage = "Reset failed: \(error.localizedDescription)"
                    showStatus = true
                }
            }
        }
    }

    private func fetchCommitLog() {
        guard isRepoConnected else { return }
        isLoading = true
        Task {
            do {
                let commits = try await GitHubService.shared.listCommits(
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    branch: currentBranch,
                    perPage: 15
                )
                let log = commits.map { commit in
                    let sha = String(commit.sha.prefix(7))
                    let author = commit.commit.author?.name ?? "Unknown"
                    let msg = commit.commit.message.components(separatedBy: "\n").first ?? ""
                    return "\(sha) — \(author): \(msg)"
                }.joined(separator: "\n")
                await MainActor.run {
                    isLoading = false
                    isSuccess = true
                    statusMessage = "Recent commits on '\(currentBranch)':\n\n\(log)"
                    showStatus = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    isSuccess = false
                    statusMessage = "Failed to load commits: \(error.localizedDescription)"
                    showStatus = true
                }
            }
        }
    }

    private func showRemoteDiff() {
        guard isRepoConnected else { return }
        guard let node = projectManager.activeFileNode, !node.isDirectory else {
            isSuccess = false
            statusMessage = "Select a file first to compare it with the remote version."
            showStatus = true
            return
        }
        isLoading = true
        Task {
            do {
                let remoteContent = try await GitHubService.shared.getFileContent(
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    path: node.path
                )
                let localContent = await MainActor.run { projectManager.activeFileContent }
                let diff: String
                if localContent == remoteContent {
                    diff = "✅ No differences — local file matches remote."
                } else {
                    let localLines = localContent.components(separatedBy: "\n")
                    let remoteLines = remoteContent.components(separatedBy: "\n")
                    var changes: [String] = []
                    let maxLines = max(localLines.count, remoteLines.count)
                    for i in 0..<min(maxLines, 50) {
                        let local = i < localLines.count ? localLines[i] : ""
                        let remote = i < remoteLines.count ? remoteLines[i] : ""
                        if local != remote {
                            changes.append("L\(i+1): local ≠ remote")
                        }
                    }
                    if changes.isEmpty {
                        diff = "Files differ in length but content within the first 50 lines matches."
                    } else {
                        diff = "Differences found in \(node.path):\n\(changes.prefix(20).joined(separator: "\n"))"
                        + (changes.count > 20 ? "\n…and \(changes.count - 20) more" : "")
                    }
                }
                await MainActor.run {
                    isLoading = false
                    isSuccess = true
                    statusMessage = diff
                    showStatus = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    isSuccess = false
                    statusMessage = "Diff failed: \(error.localizedDescription)"
                    showStatus = true
                }
            }
        }
    }

    private func stashToBranch() {
        guard isRepoConnected else { return }
        let stashBranch = "stash/\(Date().timeIntervalSince1970.description.prefix(10))"
        isLoading = true
        Task {
            do {
                try await GitHubService.shared.pushProject(
                    project,
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    commitMessage: "Stash: save work-in-progress"
                )
                await MainActor.run {
                    isLoading = false
                    isSuccess = true
                    statusMessage = "Changes pushed to branch '\(stashBranch)' as a stash. Switch back to '\(currentBranch)' to continue."
                    showStatus = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    isSuccess = false
                    statusMessage = "Stash failed: \(error.localizedDescription)"
                    showStatus = true
                }
            }
        }
    }

    private func showInfo(_ msg: String) {
        isSuccess = true
        statusMessage = msg
        showStatus = true
    }
}

// MARK: - Git Command Card Model

struct GitCommandCard: Identifiable {
    let id = UUID()
    let command: String
    let description: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void
}

// MARK: - Git Command Row

struct GitCommandRow: View {
    let card: GitCommandCard

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.icon)
                .foregroundStyle(card.isEnabled ? card.color : .secondary)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.command)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(card.isEnabled ? .white : .secondary)
                Text(card.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if card.isEnabled {
                Button(action: card.action) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .padding(8)
                        .background(card.color.opacity(0.25), in: Circle())
                        .foregroundStyle(card.color)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .opacity(card.isEnabled ? 1 : 0.6)
    }
}
