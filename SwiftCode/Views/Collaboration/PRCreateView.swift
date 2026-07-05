import SwiftUI

struct PRCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: CollaborationManager
    let actorID: String

    @State private var title = ""
    @State private var description = ""
    @State private var sourceBranchID: UUID
    @State private var targetBranchID: UUID
    @State private var isDraft = false
    @State private var includeEmpty = false
    @State private var selectedCommitIDs = Set<UUID>()
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(manager: CollaborationManager, actorID: String, preferredSourceBranchID: UUID? = nil, preferredTargetBranchID: UUID? = nil, preparedPayload: PullRequestDraftPayload? = nil) {
        self.manager = manager
        self.actorID = actorID
        let fallback = manager.branches.currentBranch.id
        _title = State(initialValue: preparedPayload?.title ?? "")
        _description = State(initialValue: preparedPayload?.description ?? "")
        _sourceBranchID = State(initialValue: preparedPayload?.sourceBranchID ?? preferredSourceBranchID ?? fallback)
        _targetBranchID = State(initialValue: preparedPayload?.targetBranchID ?? preferredTargetBranchID ?? manager.branches.branches.first(where: { $0.id != (preparedPayload?.sourceBranchID ?? preferredSourceBranchID ?? fallback) })?.id ?? fallback)
        _selectedCommitIDs = State(initialValue: Set(preparedPayload?.linkedCommitIDs ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Information") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                    Toggle("Create As Draft", isOn: $isDraft)
                    Toggle("Empty Pull Request", isOn: $includeEmpty)
                }

                Section("Branches") {
                    Picker("Source", selection: $sourceBranchID) {
                        ForEach(manager.branches.branches) { branch in
                            Text(branch.name).tag(branch.id)
                        }
                    }

                    Picker("Target", selection: $targetBranchID) {
                        let targetCandidates = manager.branches.branches.filter { $0.id != sourceBranchID }
                        if targetCandidates.isEmpty {
                            Text("No target branch available").tag(sourceBranchID)
                        } else {
                            ForEach(targetCandidates) { branch in
                                Text(branch.name).tag(branch.id)
                            }
                        }
                    }
                }

                Section("Commits Included") {
                    let commits = manager.commits.commits(for: sourceBranchID)
                    if commits.isEmpty {
                        Text("No commits on source branch.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(commits) { commit in
                        PRCommitSelectionRow(title: commit.message, subtitle: "\(commit.authorID)", isSelected: selectedCommitIDs.contains(commit.id)) {
                            if selectedCommitIDs.contains(commit.id) {
                                selectedCommitIDs.remove(commit.id)
                            } else {
                                selectedCommitIDs.insert(commit.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Pull Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating..." : "Create") {
                        createPR()
                    }
                    .disabled(isCreating)
                }
            }
            .alert(
                "Unable To Create PR",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                actions: {
                    Button("OK") { errorMessage = nil }
                },
                message: {
                    Text(errorMessage ?? "Unknown error")
                }
            )
            .onChange(of: sourceBranchID) {
                if sourceBranchID == targetBranchID,
                   let fallback = manager.branches.branches.first(where: { $0.id != sourceBranchID })?.id {
                    targetBranchID = fallback
                }
                let validCommitIDs = Set(manager.commits.commits(for: sourceBranchID).map(\.id))
                selectedCommitIDs = selectedCommitIDs.intersection(validCommitIDs)
            }
        }
    }

    private func createPR() {
        guard sourceBranchID != targetBranchID else {
            errorMessage = "Source and target branches must be different."
            return
        }

        isCreating = true
        let commits = manager.commits.commits(for: sourceBranchID).filter { selectedCommitIDs.contains($0.id) }
        defer { isCreating = false }

        if commits.isEmpty == false || includeEmpty {
            manager.createPullRequest(
                sourceID: sourceBranchID,
                targetID: targetBranchID,
                title: title,
                description: description,
                actorID: actorID,
                status: isDraft ? .draft : .open,
                linkedCommitIDs: commits.map(\.id)
            )
            dismiss()
        } else {
            errorMessage = "Select at least one commit or enable Empty Pull Request."
        }
    }
}

private struct PRCommitSelectionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
