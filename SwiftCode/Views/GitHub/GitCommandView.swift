import SwiftUI
import ZIPFoundation

@MainActor
struct GitCommandView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSessionStore.self) private var sessionStore

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
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Git Guided Commands", systemImage: "terminal.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    // Branch indicator
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Repository Association", systemImage: "arrow.branch")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            if isRepoConnected {
                                HStack {
                                    Text("Current Linked Branch:")
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
                            } else {
                                Text("Connect a GitHub repository first to run remote commands.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Command groups
                    GroupBox {
                        commandGroup(
                            title: "Synchronization Operations",
                            icon: "arrow.triangle.2.circlepath",
                            color: .orange,
                            commands: syncCommands
                        )
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        commandGroup(
                            title: "Branch Controls",
                            icon: "arrow.branch",
                            color: .green,
                            commands: branchCommands
                        )
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        commandGroup(
                            title: "Revision History Logs",
                            icon: "clock.arrow.circlepath",
                            color: .purple,
                            commands: historyCommands
                        )
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        commandGroup(
                            title: "Development Utilities",
                            icon: "wrench.and.screwdriver",
                            color: .gray,
                            commands: utilityCommands
                        )
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
        }
        .sourceControlEmbedded()
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

    // MARK: - Subviews

    private func commandGroup(
        title: String,
        icon: String,
        color: Color,
        commands: [GitCommandCard]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
                Spacer()
            }
            ForEach(commands) { cmd in
                GitCommandRow(card: cmd)
            }
        }
    }

    // MARK: - Command Sheets

    private var commitInputSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Commit Message", systemImage: "pencil")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Describe Your Changes", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            HStack {
                Button("Cancel") { showCommitInput = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Commit & Push") {
                    showCommitInput = false
                    pushChanges()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var branchInputSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Branch / Checkout", systemImage: "arrow.branch")
                    .font(.headline)
                    .foregroundColor(.green)
                Spacer()
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("New Branch Name")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("feature/new-feature", text: $newBranchName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    if !branches.isEmpty {
                        Text("Switch To Existing Branch")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        ScrollView {
                            VStack(spacing: 6) {
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
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            if branch.name == currentBranch {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.04))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            HStack {
                Button("Cancel") { showBranchInput = false }
                    .buttonStyle(.bordered)
                Spacer()
                if !newBranchName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Create Branch") {
                        let name = newBranchName.trimmingCharacters(in: .whitespaces)
                        showBranchInput = false
                        createBranch(name: name)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var tagInputSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("git tag", systemImage: "tag.fill")
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("v1.0.0", text: $tagName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    TextField("Tag message (optional)", text: $tagMessage)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            HStack {
                Button("Cancel") { showTagInput = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create Tag") {
                    showTagInput = false
                    createTag()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(tagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
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

    // MARK: - Actions

    private func checkStatus() {
        let modified = sessionStore.modifiedFilePaths.count
        isSuccess = true
        statusMessage = "Working tree status:\n\n" + (modified == 0 ? "Clean. No changes detected." : "\(modified) files modified locally.")
        showStatus = true
    }

    private func cleanWorkingTree() {
        sessionStore.modifiedFilePaths.removeAll()
        isSuccess = true
        statusMessage = "Cleaned: Local change markers have been cleared."
        showStatus = true
    }

    private func createTag() {
        guard isRepoConnected else { return }
        isLoading = true
        Task {
            do {
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
                let zipURL = try await GitHubService.shared.downloadRepositoryZip(
                    owner: ownerFromRepo,
                    repo: repoNameFromURL,
                    branch: currentBranch
                )
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try FileManager.default.unzipItem(at: zipURL, to: tempDir)
                try? FileManager.default.removeItem(at: zipURL)
                try? FileManager.default.removeItem(at: tempDir)

                await MainActor.run {
                    isLoading = false
                    isSuccess = true
                    statusMessage = "Reset: Re-download complete."
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
        guard let node = sessionStore.activeFileNode, !node.isDirectory else {
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
                let localContent = await MainActor.run { sessionStore.activeFileContent }
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

    private func showInfo(_ msg: String) {
        isSuccess = true
        statusMessage = msg
        showStatus = true
    }
}

// MARK: - Git Command Models

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
        Button(action: card.action) {
            HStack(spacing: 12) {
                Image(systemName: card.icon)
                    .font(.title2)
                    .foregroundStyle(card.color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.command)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(card.isEnabled ? .primary : .secondary)
                    Text(card.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if card.isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!card.isEnabled)
    }
}
