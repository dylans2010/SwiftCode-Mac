import SwiftUI

struct BranchWorkspaceView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String

    @State private var selectedFilePath: String?
    @State private var editorText = ""
    @State private var newFilePath = ""
    @State private var commitMessage = ""
    @State private var newBranchName = ""
    @State private var pullRequestTargetID: UUID?
    @State private var showingCommitManager = false
    @State private var showingCreatePRSheet = false
    @State private var preparedPullRequest: PullRequestDraftPayload?
    @State private var localErrorMessage: String?

    private var workspace: BranchWorkspace? { manager.workspaces.currentWorkspace }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                filesSection
                changesSection
                actionsSection
            }
            .padding()
        }
        .background(Color.clear)
        .navigationTitle("Branches")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if manager.workspaces.isLoadingWorkspace {
                    ProgressView()
                }
                Menu {
                    ForEach(manager.branches.branches) { branch in
                        Button(branch.name) {
                            _ = manager.workspaces.loadWorkspace(for: branch.id, actorID: actorID)
                            selectCurrentFileIfNeeded()
                        }
                    }
                } label: {
                    Label("Switch Branch", systemImage: "arrow.triangle.branch")
                }
            }
        }
        .sheet(isPresented: $showingCommitManager) {
            NavigationStack {
                CommitManagerView(manager: manager, actorID: actorID)
            }
        }
        .sheet(isPresented: $showingCreatePRSheet) {
            if let currentBranch = workspace?.branchID {
                PRCreateView(manager: manager, actorID: actorID, preferredSourceBranchID: currentBranch, preferredTargetBranchID: pullRequestTargetID, preparedPayload: preparedPullRequest)
            }
        }
        .alert(
            "Branch Error",
            isPresented: Binding(
                get: { localErrorMessage != nil },
                set: { if !$0 { localErrorMessage = nil } }
            ),
            actions: { Button("OK") { localErrorMessage = nil } },
            message: { Text(localErrorMessage ?? "Unknown error") }
        )
        .onAppear {
            if workspace == nil {
                _ = manager.workspaces.loadWorkspace(for: manager.branches.currentBranch.id, actorID: actorID)
            }
            selectCurrentFileIfNeeded()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .textCase(.uppercase)
                    Text(workspace?.branchName ?? "No Branch")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .font(.title)
                    .foregroundStyle(.blue.opacity(0.8))
            }

            if let workspace {
                HStack(spacing: 16) {
                    statBadge(title: "Files", value: "\(workspace.files.count)", icon: "doc.fill")
                    statBadge(title: "Changes", value: "\(workspace.pendingChanges.count)", icon: "plus.forwardslash.minus")
                    statBadge(title: "Commits", value: "\(manager.commits.commits(for: workspace.branchID).count)", icon: "shippingbox.fill")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Create New Branch")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Branch Name", text: $newBranchName)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            let sanitizedName = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard sanitizedName.isEmpty == false else { return }
                            guard manager.branches.branches.contains(where: { $0.name.caseInsensitiveCompare(sanitizedName) == .orderedSame }) == false else {
                                localErrorMessage = "A branch named '\(sanitizedName)' already exists."
                                return
                            }
                            let branch = manager.branches.createBranch(name: sanitizedName, from: manager.branches.currentBranch.id, actorID: actorID)
                            _ = manager.workspaces.createWorkspace(for: branch, from: manager.branches.currentBranch.id, actorID: actorID)
                            newBranchName = ""
                            selectCurrentFileIfNeeded()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Work on changes without affecting main")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Files")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }

            if let workspace {
                HStack {
                    TextField("New File Path", text: $newFilePath)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button {
                        manager.workspaces.createFile(path: newFilePath, authorID: actorID)
                        newFilePath = ""
                        selectCurrentFileIfNeeded()
                    } label: {
                        Image(systemName: "doc.badge.plus")
                            .foregroundStyle(.blue)
                    }
                    .disabled(newFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                VStack(spacing: 12) {
                    ForEach(workspace.files.sorted { $0.path < $1.path }) { file in
                        VStack(spacing: 0) {
                            Button {
                                withAnimation {
                                    if selectedFilePath == file.path {
                                        selectedFilePath = nil
                                    } else {
                                        selectedFilePath = file.path
                                        editorText = file.content
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.blue)
                                    Text(file.path)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Button(role: .destructive) {
                                        manager.workspaces.deleteFile(path: file.path, authorID: actorID)
                                        if selectedFilePath == file.path {
                                            selectedFilePath = nil
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundStyle(.red.opacity(0.7))
                                    }
                                }
                                .padding()
                            }

                            if selectedFilePath == file.path {
                                VStack(spacing: 12) {
                                    TextEditor(text: $editorText)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(height: 200)
                                        .padding(8)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Button {
                                        manager.workspaces.updateFile(path: file.path, content: editorText, authorID: actorID)
                                    } label: {
                                        Label("Save Changes", systemImage: "checkmark.circle")
                                            .font(.caption.bold())
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.blue.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.02))
                            }
                        }
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var changesSection: some View {
        Section("Active Changes") {
            if let workspace, workspace.pendingChanges.isEmpty {
                Text("No Uncommitted Changes")
                    .foregroundStyle(.secondary)
            } else if let workspace {
                ForEach(workspace.pendingChanges) { change in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(change.path).font(.headline)
                                Text(change.kind.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(change.isStaged ? "Unstage" : "Stage") {
                                if change.isStaged {
                                    manager.commits.unstage(path: change.path, actorID: actorID, branchID: workspace.branchID)
                                } else {
                                    manager.commits.stage(path: change.path, authorID: actorID, branchID: workspace.branchID)
                                }
                                manager.workspaces.syncWorkspaceStateFromCommitManager()
                            }
                        }
                        NavigationLink("View Diff") {
                            CollaborationDiffViewerView(diff: change.diff)
                        }
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            TextField("Commit message", text: $commitMessage)
            Button {
                _ = manager.workspaces.commitCurrentWorkspace(message: commitMessage, authorID: actorID)
                commitMessage = ""
            } label: {
                Label("Commit Changes", systemImage: "checkmark.circle.fill")
            }
            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                showingCommitManager = true
            } label: {
                Label("Open Commit Flow", systemImage: "shippingbox.circle")
            }

            Button(role: .destructive) {
                manager.workspaces.discardChanges()
                selectCurrentFileIfNeeded()
            } label: {
                Label("Discard Changes", systemImage: "arrow.uturn.backward.circle")
            }

            Button {
                manager.workspaces.resetToLastCommit()
                selectCurrentFileIfNeeded()
            } label: {
                Label("Reset to Last Commit", systemImage: "clock.arrow.circlepath")
            }

            Picker("PR Target", selection: Binding(get: {
                pullRequestTargetID ?? manager.branches.branches.first(where: { $0.id != manager.branches.currentBranch.id })?.id
            }, set: { pullRequestTargetID = $0 })) {
                Text("Select target branch").tag(UUID?.none)
                ForEach(manager.branches.branches.filter { $0.id != manager.branches.currentBranch.id }) { branch in
                    Text(branch.name).tag(Optional(branch.id))
                }
            }

            Button {
                if let target = pullRequestTargetID ?? manager.branches.branches.first(where: { $0.id != manager.branches.currentBranch.id })?.id {
                    preparedPullRequest = manager.workspaces.preparePullRequestPayload(targetBranchID: target, actorID: actorID)
                }
                showingCreatePRSheet = true
            } label: {
                Label("Create Pull Request", systemImage: "arrow.triangle.pull")
            }
            .disabled(manager.branches.branches.count < 2)
        }
    }

    private var statusSection: some View {
        Section {
            if let success = manager.workspaces.lastSuccessMessage {
                Label(success, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let error = manager.workspaces.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func statBadge(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func selectCurrentFileIfNeeded() {
        guard let workspace else { return }
        if let selectedFilePath, let file = workspace.files.first(where: { $0.path == selectedFilePath }) {
            editorText = file.content
        } else if let first = workspace.files.first {
            selectedFilePath = first.path
            editorText = first.content
        }
    }
}
