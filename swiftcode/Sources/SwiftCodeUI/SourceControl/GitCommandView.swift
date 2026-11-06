import SwiftCodeGitHub
import SwiftCodeIDECore
import SwiftCodeSubprocess
import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/GitCommandView.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// A browser of git command cards, grouped by Sync / Branch / History /
/// Utility, with a console that shows each command's real output.
///
/// Legacy's actions were partly fake and are NOT re-ported as fakes:
/// - `createTag` slept 1s and claimed success → now `GitRepository.createTag`.
/// - `pullChanges` only showed an info message → now `GitRepository.pull()`.
/// - `createBranch` only set state → now `GitRepository.createBranch`.
/// - `cleanWorkingTree` only cleared markers → now real `git clean -fd`
///   (behind a confirmation — it deletes untracked files).
/// - `checkStatus` read a cached marker list → now `GitRepository.status()`.
///
/// Local cards run against `repository`. Remote cards (remote branches,
/// remote commits, file diff against the remote) need `client` + `remote`
/// and are disabled when either is nil. The diff card also needs
/// `activeFile` (path + current editor content) to compare against the
/// remote version.
///
/// Hook: present from the source-control navigator with the navigator's
/// repository, a `GitHubClient` when the project has a GitHub remote, and
/// the active editor file for the diff card.
@MainActor
public struct GitCommandView: View {
    public var repository: GitRepository
    public var client: GitHubClient?
    public var remote: (owner: String, repo: String)?
    /// The file open in the editor, for the "Diff vs remote" card.
    public var activeFile: (path: String, content: String)?

    @State private var consoleOutput = ""
    @State private var isRunning = false
    @State private var runningCard: GitCommandCard.ID?

    @State private var showCommitSheet = false
    @State private var commitMessage = ""
    @State private var showBranchSheet = false
    @State private var newBranchName = ""
    @State private var showTagSheet = false
    @State private var newTagName = ""
    @State private var newTagMessage = ""
    @State private var showSwitchSheet = false
    @State private var switchBranchName = ""
    @State private var showCherryPick = false
    @State private var confirmDestructive: GitCommandCard.ID?

    public init(
        repository: GitRepository,
        client: GitHubClient? = nil,
        remote: (owner: String, repo: String)? = nil,
        activeFile: (path: String, content: String)? = nil
    ) {
        self.repository = repository
        self.client = client
        self.remote = remote
        self.activeFile = activeFile
    }

    private var cards: [GitCommandCard] {
        let hasRemote = client != nil && remote != nil
        return [
            GitCommandCard(id: "status", group: "Sync", title: "Status", description: "Show working-tree status", icon: "info.circle"),
            GitCommandCard(id: "commit-push", group: "Sync", title: "Commit & Push", description: "Stage all, commit, and push", icon: "arrow.up.to.line"),
            GitCommandCard(id: "push", group: "Sync", title: "Push", description: "Push the current branch upstream", icon: "arrow.up.circle"),
            GitCommandCard(id: "pull", group: "Sync", title: "Pull", description: "Fast-forward pull from upstream", icon: "arrow.down.circle"),
            GitCommandCard(id: "fetch", group: "Sync", title: "Fetch", description: "Fetch all remotes and prune", icon: "arrow.down.to.line"),
            GitCommandCard(id: "create-branch", group: "Branch", title: "Create Branch", description: "Create and check out a new branch", icon: "plus"),
            GitCommandCard(id: "switch-branch", group: "Branch", title: "Switch Branch", description: "Check out another local branch", icon: "arrow.triangle.swap"),
            GitCommandCard(id: "remote-branches", group: "Branch", title: "Remote Branches", description: "List branches on the GitHub remote", icon: "cloud", isEnabled: hasRemote),
            GitCommandCard(id: "log", group: "History", title: "Log", description: "Recent local commits", icon: "clock.arrow.circlepath"),
            GitCommandCard(id: "remote-commits", group: "History", title: "Remote Commits", description: "Recent commits on the GitHub remote", icon: "cloud", isEnabled: hasRemote),
            GitCommandCard(id: "diff-remote", group: "History", title: "Diff vs Remote", description: "Diff the open file against the remote version", icon: "arrow.left.and.right", isEnabled: hasRemote && activeFile != nil),
            GitCommandCard(id: "cherry-pick", group: "History", title: "Cherry-Pick", description: "Apply a commit onto this branch", icon: "arrow.down.to.line.compound"),
            GitCommandCard(id: "create-tag", group: "Utility", title: "Create Tag", description: "Tag the current commit", icon: "tag"),
            GitCommandCard(id: "clean", group: "Utility", title: "Clean Working Tree", description: "Delete untracked files and directories", icon: "trash", isDestructive: true),
            GitCommandCard(id: "reset-hard", group: "Utility", title: "Reset --hard", description: "Discard all uncommitted changes", icon: "arrow.counterclockwise", isDestructive: true),
        ]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Git Commands")
                .font(.headline)
            ForEach(["Sync", "Branch", "History", "Utility"], id: \.self) { group in
                commandGroup(group)
            }
            Divider()
            console
        }
        .padding()
        .sheet(isPresented: $showCommitSheet) { commitSheet }
        .sheet(isPresented: $showBranchSheet) { branchSheet }
        .sheet(isPresented: $showTagSheet) { tagSheet }
        .sheet(isPresented: $showSwitchSheet) { switchSheet }
        .sheet(isPresented: $showCherryPick) {
            NSCherryPickView(repository: repository)
        }
        .alert("This cannot be undone", isPresented: Binding(
            get: { confirmDestructive != nil },
            set: { if !$0 { confirmDestructive = nil } }
        )) {
            Button("Run", role: .destructive) {
                if let id = confirmDestructive {
                    Task { await runCard(id) }
                }
                confirmDestructive = nil
            }
            Button("Cancel", role: .cancel) { confirmDestructive = nil }
        } message: {
            Text(destructiveWarning)
        }
    }

    private var destructiveWarning: String {
        switch confirmDestructive {
        case "clean": return "Deletes every untracked file and directory in the working tree."
        case "reset-hard": return "Discards every uncommitted change in the working tree."
        default: return "This operation cannot be undone."
        }
    }

    private func commandGroup(_ group: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], spacing: 8) {
                ForEach(cards.filter { $0.group == group }) { card in
                    GitCommandRow(card: card, isRunning: runningCard == card.id) {
                        tapCard(card)
                    }
                }
            }
        }
    }

    private var console: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { consoleOutput = "" }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            ScrollView {
                Text(consoleOutput.isEmpty ? "Pick a command card to run it." : consoleOutput)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(minHeight: 140)
        }
    }

    private var commitSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Commit & Push")
                .font(.headline)
            TextField("Commit message", text: $commitMessage)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showCommitSheet = false }
                    .buttonStyle(.bordered)
                Button("Commit & Push") {
                    showCommitSheet = false
                    Task { await runCard("commit-push") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var branchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Branch")
                .font(.headline)
            TextField("Branch name", text: $newBranchName)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Spacer()
                Button("Cancel") { showBranchSheet = false }
                    .buttonStyle(.bordered)
                Button("Create & Switch") {
                    showBranchSheet = false
                    Task { await runCard("create-branch") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var tagSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Tag")
                .font(.headline)
            TextField("Tag name (e.g. v1.2.0)", text: $newTagName)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            TextField("Annotation message (optional)", text: $newTagMessage)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showTagSheet = false }
                    .buttonStyle(.bordered)
                Button("Create Tag") {
                    showTagSheet = false
                    Task { await runCard("create-tag") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var switchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Switch Branch")
                .font(.headline)
            Picker("Branch", selection: $switchBranchName) {
                ForEach(localBranches, id: \.self) { branch in
                    Text(branch).tag(branch)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Spacer()
                Button("Cancel") { showSwitchSheet = false }
                    .buttonStyle(.bordered)
                Button("Switch") {
                    showSwitchSheet = false
                    Task { await runCard("switch-branch") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(switchBranchName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            if switchBranchName.isEmpty, let first = localBranches.first {
                switchBranchName = first
            }
        }
    }

    private var localBranches: [String] {
        (try? repository.branches().map(\.name)) ?? []
    }

    private func tapCard(_ card: GitCommandCard) {
        guard card.isEnabled, !isRunning else { return }
        switch card.id {
        case "commit-push": showCommitSheet = true
        case "create-branch": showBranchSheet = true
        case "create-tag": showTagSheet = true
        case "switch-branch": showSwitchSheet = true
        case "cherry-pick": showCherryPick = true
        case "clean", "reset-hard": confirmDestructive = card.id
        default: Task { await runCard(card.id) }
        }
    }

    private func runCard(_ id: String) async {
        isRunning = true
        runningCard = id
        defer { isRunning = false; runningCard = nil }
        let repository = repository
        do {
            switch id {
            case "status":
                let status = try await Task.detached { try repository.status() }.value
                appendOutput("Working tree: \(status.count) changed file(s)\n")
                for (path, fileStatus) in status.sorted(by: { $0.key < $1.key }) {
                    appendOutput("  \(fileStatus.rawValue) \(path)\n")
                }
                if status.isEmpty { appendOutput("  clean\n") }
            case "commit-push":
                let message = commitMessage
                let hash = try await Task.detached {
                    try repository.stageAll()
                    let hash = try repository.commitStaged(message: message)
                    try repository.push()
                    return hash
                }.value
                appendOutput("Committed \(hash) and pushed.\n")
                commitMessage = ""
            case "push":
                try await Task.detached { try repository.push() }.value
                appendOutput("Pushed.\n")
            case "pull":
                try await Task.detached { try repository.pull() }.value
                appendOutput("Pulled (fast-forward).\n")
            case "fetch":
                try await Task.detached { try repository.fetch() }.value
                appendOutput("Fetched all remotes.\n")
            case "create-branch":
                let name = newBranchName.trimmingCharacters(in: .whitespaces)
                try await Task.detached { try repository.createBranch(name, checkout: true) }.value
                appendOutput("Created and checked out branch \(name).\n")
                newBranchName = ""
            case "switch-branch":
                let name = switchBranchName
                try await Task.detached { try repository.switchBranch(name) }.value
                appendOutput("Switched to \(name).\n")
            case "remote-branches":
                guard let client, let remote else { break }
                let branches = try await client.listBranches(owner: remote.owner, repo: remote.repo, perPage: 100)
                appendOutput("Remote branches (\(branches.count)):\n")
                for branch in branches { appendOutput("  \(branch.name)\n") }
            case "log":
                let commits = await Task.detached { repository.log(limit: 20) }.value
                appendOutput("Recent commits (\(commits.count)):\n")
                for commit in commits {
                    appendOutput("  \(commit.shortHash) \(commit.subject)\n")
                }
            case "remote-commits":
                guard let client, let remote else { break }
                let commits = try await client.listCommits(owner: remote.owner, repo: remote.repo, perPage: 20)
                appendOutput("Remote commits (\(commits.count)):\n")
                for commit in commits {
                    appendOutput("  \(String(commit.sha.prefix(7))) \(commit.message.split(separator: "\n").first ?? "")\n")
                }
            case "diff-remote":
                guard let client, let remote, let activeFile else { break }
                let remoteText = try await client.getFileText(owner: remote.owner, repo: remote.repo, path: activeFile.path)
                if remoteText == activeFile.content {
                    appendOutput("\(activeFile.path) matches the remote version.\n")
                } else {
                    let remoteLines = remoteText.split(separator: "\n", omittingEmptySubsequences: false)
                    let localLines = activeFile.content.split(separator: "\n", omittingEmptySubsequences: false)
                    appendOutput("\(activeFile.path): remote \(remoteLines.count) lines, local \(localLines.count) lines — differs.\n")
                    appendOutput("Open the file in the diff viewer for the line-by-line diff.\n")
                }
            case "create-tag":
                let name = newTagName.trimmingCharacters(in: .whitespaces)
                let message = newTagMessage.trimmingCharacters(in: .whitespaces)
                try await Task.detached {
                    try repository.createTag(name, message: message.isEmpty ? nil : message)
                }.value
                appendOutput("Created tag \(name).\n")
                newTagName = ""
                newTagMessage = ""
            case "clean":
                let gitPath = GitRepository.resolvedGitPath()
                let root = repository.root
                let output = try await Task.detached {
                    try Subprocess.run(gitPath, ["clean", "-fd"], currentDirectory: root)
                }.value
                appendOutput(output.stdoutText.isEmpty ? "Working tree clean.\n" : output.stdoutText)
            case "reset-hard":
                let gitPath = GitRepository.resolvedGitPath()
                let root = repository.root
                _ = try await Task.detached {
                    try Subprocess.run(gitPath, ["reset", "--hard", "HEAD"], currentDirectory: root)
                }.value
                appendOutput("Reset --hard to HEAD; uncommitted changes discarded.\n")
            default:
                break
            }
        } catch {
            appendOutput("Failed: \(error.localizedDescription)\n")
        }
        appendOutput("\n")
    }

    private func appendOutput(_ text: String) {
        consoleOutput += text
    }
}

/// One card in the git command browser.
public struct GitCommandCard: Identifiable {
    public typealias ID = String
    public var id: String
    public var group: String
    public var title: String
    public var description: String
    public var icon: String
    public var isEnabled: Bool
    public var isDestructive: Bool

    public init(id: String, group: String, title: String, description: String, icon: String, isEnabled: Bool = true, isDestructive: Bool = false) {
        self.id = id
        self.group = group
        self.title = title
        self.description = description
        self.icon = icon
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
    }
}

/// One card row in the git command browser.
public struct GitCommandRow: View {
    public var card: GitCommandCard
    public var isRunning: Bool
    public var action: () -> Void

    public init(card: GitCommandCard, isRunning: Bool, action: @escaping () -> Void) {
        self.card = card
        self.isRunning = isRunning
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: card.icon)
                    .foregroundStyle(card.isDestructive ? .red : .accentColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title)
                        .font(.subheadline.bold())
                    Text(card.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!card.isEnabled)
    }
}
