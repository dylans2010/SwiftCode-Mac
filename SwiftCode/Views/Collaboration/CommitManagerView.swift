import SwiftUI

struct CommitManagerView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String

    @State private var commitMessage = ""
    @State private var customPath = ""
    @State private var customDiff = ""
    @State private var selectedKind: CommitChangeKind = .modified
    @State private var operationMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                branchContextCard()
                workingTreeSection()
                createCommitSection()
                historySection()

                if let operationMessage {
                    Label(operationMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding()
        }
        .background(Color.clear)
        .navigationTitle("Commit Manager")
    }

    @ViewBuilder
    private func branchContextCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Branch Context")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .textCase(.uppercase)
                    Text(manager.branches.currentBranch.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "shippingbox.circle")
                    .font(.title)
                    .foregroundStyle(.blue.opacity(0.8))
            }

            HStack(spacing: 12) {
                actionButton(title: "Undo", icon: "arrow.uturn.backward", tint: .orange, enabled: manager.commits.canUndo) {
                    _ = manager.commits.undo()
                }
                actionButton(title: "Redo", icon: "arrow.uturn.forward", tint: .blue, enabled: manager.commits.canRedo) {
                    _ = manager.commits.redo()
                }
            }

            Text("Working changes and history are isolated to this branch.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private func workingTreeSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Working Tree")
                .font(.headline)
                .foregroundStyle(.white)

            workingTreeEditor
            workingChangesList
        }
        .padding(20)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var workingTreeEditor: some View {
        VStack(spacing: 12) {
            TextField("File Path", text: $customPath)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Picker("Change Type", selection: $selectedKind) {
                ForEach(CommitChangeKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue.capitalized).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextField("Diff content", text: $customDiff, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .lineLimit(3...8)

            Button(action: addOrUpdateChange) {
                Label("Add / Update Change", systemImage: "plus.circle")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isAddChangeDisabled)
        }
    }

    @ViewBuilder
    private var workingChangesList: some View {
        if manager.commits.workingChanges.isEmpty {
            Text("No working changes on this branch yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(spacing: 12) {
                ForEach(manager.commits.workingChanges) { change in
                    WorkingChangeRow(
                        change: change,
                        onStageToggle: toggleStage(for:)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func createCommitSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Commit")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                TextField("Commit Message", text: $commitMessage)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    manager.commit(message: commitMessage, authorID: actorID, changes: [:])
                    manager.workspaces.syncWorkspaceStateFromCommitManager()
                    commitMessage = ""
                    operationMessage = "Commit Created Successfully."
                } label: {
                    Label("Commit Staged Changes", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.commits.stagedChanges.isEmpty)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private func historySection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                ForEach(manager.commits.commits(for: manager.branches.currentBranch.id)) { commit in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(commit.message).font(.subheadline.bold()).foregroundStyle(.white)
                                Text("\(commit.authorID) • \(commit.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Undo Last Commit") { _ = manager.commits.undo() }
                                Button("Revert Commit") {
                                    _ = manager.commits.revert(commitID: commit.id, actorID: actorID)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(commit.changes.keys.sorted(), id: \.self) { path in
                                    NavigationLink {
                                        CollaborationDiffViewerView(diff: commit.changes[path] ?? "")
                                    } label: {
                                        Label(path, systemImage: "doc.text")
                                            .font(.system(size: 10))
                                            .padding(6)
                                            .background(Color.white.opacity(0.05))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var isAddChangeDisabled: Bool {
        customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        customDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addOrUpdateChange() {
        manager.commits.updateWorkingChange(
            path: customPath,
            diff: customDiff,
            kind: selectedKind,
            authorID: actorID,
            branchID: manager.branches.currentBranch.id
        )
        manager.workspaces.syncWorkspaceStateFromCommitManager()
        customPath = ""
        customDiff = ""
    }

    private func toggleStage(for change: CommitFileChange) {
        if change.isStaged {
            manager.commits.unstage(path: change.path, actorID: actorID, branchID: manager.branches.currentBranch.id)
        } else {
            manager.commits.stage(path: change.path, authorID: actorID, branchID: manager.branches.currentBranch.id)
        }
    }

    private func actionButton(title: String, icon: String, tint: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tint.opacity(0.2))
                .foregroundStyle(tint)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled)
    }
}

private struct WorkingChangeRow: View {
    let change: CommitFileChange
    let onStageToggle: (CommitFileChange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            diffLink
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.path)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(change.kind.rawValue.capitalized) • \(change.authorID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(change.isStaged ? "Unstage" : "Stage") {
                onStageToggle(change)
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(change.isStaged ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
            .foregroundStyle(change.isStaged ? .orange : .blue)
            .clipShape(Capsule())
        }
    }

    private var diffLink: some View {
        NavigationLink {
            CollaborationDiffViewerView(diff: change.diff)
        } label: {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                Text("Open Diff")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.caption)
            .padding(8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
