import SwiftUI

// MARK: - Commit History View

struct CommitHistoryView: View {
    let owner: String
    let repo: String
    @Binding var currentBranch: String

    @State private var commits: [GitHubCommit] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedCommit: GitHubCommit?
    @State private var showDiffPreview: GitHubCommit?
    @State private var amendTarget: GitHubCommit?
    @State private var showAmendSheet = false
    @State private var amendMessage = ""
    @State private var isOperating = false
    @State private var notification: CommitNotification?
    @State private var showConflictAlert = false
    @State private var conflictDetails = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()

                if isLoading && commits.isEmpty {
                    ProgressView("Loading Commits…")
                        .tint(.orange)
                } else if let error = errorMessage, commits.isEmpty {
                    errorView(error)
                } else if commits.isEmpty {
                    emptyView
                } else {
                    commitList
                }
            }
            .navigationTitle("Commit History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await loadHistory() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.orange)
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(item: $selectedCommit) { commit in
                CommitDetailView(commit: commit, owner: owner, repo: repo)
            }
            .sheet(isPresented: $showAmendSheet) {
                amendSheet
            }
            .alert("Conflict Detected", isPresented: $showConflictAlert) {
                Button("Dismiss") {}
            } message: {
                Text(conflictDetails)
            }
            .overlay(alignment: .bottom) {
                if let n = notification {
                    commitNotificationBanner(n)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 16)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: notification != nil)
        }
        .preferredColorScheme(.dark)
        .task { await loadHistory() }
        .onChange(of: currentBranch) {
            Task { await loadHistory() }
        }
    }

    // MARK: - Commit List

    private var commitList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Branch label
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(currentBranch)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text("· \(commits.count) Commits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.05))

                Divider().opacity(0.2)

                ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                    commitRow(commit: commit, index: index)
                    Divider().opacity(0.08).padding(.leading, 50)
                }
            }
        }
    }

    private func commitRow(commit: GitHubCommit, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline dot
            VStack(spacing: 0) {
                Circle()
                    .fill(index == 0 ? Color.orange : Color.orange.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
                Rectangle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 6) {
                Text(commit.commit.message.components(separatedBy: "\n").first ?? commit.commit.message)
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let name = commit.commit.author?.name {
                        Label(name, systemImage: "person.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let date = commit.commit.author?.date {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(String(commit.sha.prefix(8)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.orange.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                    if index == 0 {
                        Text("HEAD")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                    }
                }

                // Action buttons
                HStack(spacing: 8) {
                    // Diff Preview
                    actionChip(label: "Diff", icon: "doc.text.magnifyingglass", color: .blue) {
                        showDiffPreview = commit
                        selectedCommit = commit
                    }

                    // Amend (only last commit)
                    if index == 0 {
                        actionChip(label: "Amend", icon: "pencil", color: .yellow) {
                            amendTarget = commit
                            amendMessage = commit.commit.message
                            showAmendSheet = true
                        }
                    }

                    // Revert
                    actionChip(label: "Revert", icon: "arrow.uturn.backward", color: .red) {
                        Task { await revertCommit(commit) }
                    }

                    // Cherry-pick
                    if index != 0 {
                        actionChip(label: "Cherry Pick", icon: "paintpalette", color: .purple) {
                            Task { await cherryPick(commit) }
                        }
                    }
                }
            }

            Spacer()

            Button {
                selectedCommit = commit
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.02))
        .contentShape(Rectangle())
    }

    private func actionChip(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isOperating)
    }

    // MARK: - Amend Sheet

    private var amendSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit commit message for HEAD:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                TextEditor(text: $amendMessage)
                    .font(.body)
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .frame(minHeight: 120)
                    .padding(.horizontal)

                Text("Note: Amending rewrites the last commit. Avoid amending commits already pushed to a shared branch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Amend Commit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAmendSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task { await amendLastCommit() }
                    }
                    .disabled(amendMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty / Error Views

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(.orange.opacity(0.5))
            Text("No Commits Found")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Branch \(currentBranch) has no commit history yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.red.opacity(0.7))
            Text("Failed to Load History")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") { Task { await loadHistory() } }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
    }

    // MARK: - Notification Banner

    private func commitNotificationBanner(_ n: CommitNotification) -> some View {
        HStack(spacing: 10) {
            Image(systemName: n.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(n.isError ? .red : .green)
            Text(n.message)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                    n.isError ? Color.red.opacity(0.4) : Color.green.opacity(0.4),
                    lineWidth: 1
                ))
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func loadHistory() async {
        guard !owner.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            commits = try await GitHubService.shared.listCommits(
                owner: owner,
                repo: repo,
                branch: currentBranch,
                perPage: 50
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func amendLastCommit() async {
        guard let _ = amendTarget else { return }
        showAmendSheet = false
        isOperating = true
        defer { isOperating = false }


        try? await Task.sleep(nanoseconds: 800_000_000)
        showNotification("Commit amended (placeholder – requires git push --force)", isError: false)
        await loadHistory()
    }

    private func revertCommit(_ commit: GitHubCommit) async {
        isOperating = true
        defer { isOperating = false }

        // PLACEHOLDER: Check for conflicts when applying the revert diff.
        let hasConflict = false // Replace with real conflict detection logic.
        if hasConflict {
            conflictDetails = "Conflict while reverting \(commit.commit.message). Manual resolution required."
            showConflictAlert = true
            return
        }

        try? await Task.sleep(nanoseconds: 800_000_000)
        showNotification("Revert of \(String(commit.sha.prefix(8))) created (placeholder)", isError: false)
        await loadHistory()
    }

    /// Cherry-pick a commit onto the current branch.
    /// PLACEHOLDER: Applies the diff from the selected commit to HEAD.
    private func cherryPick(_ commit: GitHubCommit) async {
        isOperating = true
        defer { isOperating = false }

        // PLACEHOLDER: Apply the commit diff to HEAD. Check for conflicts.
        let hasConflict = false // Replace with real conflict detection.
        if hasConflict {
            conflictDetails = "Conflict cherry-picking \(commit.commit.message) onto \(currentBranch). Manual resolution required."
            showConflictAlert = true
            return
        }

        // PLACEHOLDER: Commit the cherry-picked changes via the API.
        try? await Task.sleep(nanoseconds: 800_000_000)
        showNotification("Cherry-picked \(String(commit.sha.prefix(8))) (placeholder)", isError: false)
        await loadHistory()
    }

    private func showNotification(_ message: String, isError: Bool) {
        notification = CommitNotification(message: message, isError: isError)
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            notification = nil
        }
    }
}

// MARK: - Commit Detail View (with inline diff preview)

struct CommitDetailView: View {
    let commit: GitHubCommit
    let owner: String
    let repo: String

    @State private var diffContent: String = ""
    @State private var isLoadingDiff = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // SHA
                    infoCard {
                        labeledRow(label: "SHA", value: commit.sha, icon: "tag", monospaced: true, selectable: true)
                    }

                    // Message
                    infoCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Commit Message")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(commit.commit.message)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }

                    // Author
                    if let author = commit.commit.author {
                        infoCard {
                            VStack(spacing: 8) {
                                if let name = author.name {
                                    labeledRow(label: "Author", value: name, icon: "person.circle")
                                }
                                if let date = author.date {
                                    labeledRow(label: "Date", value: date.formatted(date: .long, time: .shortened), icon: "calendar")
                                }
                            }
                        }
                    }

                    // Diff Preview
                    infoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Diff Preview", systemImage: "doc.text.magnifyingglass")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Spacer()
                                if isLoadingDiff {
                                    ProgressView().scaleEffect(0.7)
                                }
                            }

                            if diffContent.isEmpty && !isLoadingDiff {
                                Text("No diff available for this commit.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            } else {
                                diffView
                            }
                        }
                    }

                    // View on GitHub
                    if let urlStr = commit.htmlUrl, let url = URL(string: urlStr) {
                        Link(destination: url) {
                            Label("View On GitHub", systemImage: "safari")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Commit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadDiff() }
    }

    private var diffView: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(diffContent.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("+++") || line.hasPrefix("---") {
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.orange)
                } else if line.hasPrefix("+") {
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green)
                } else if line.hasPrefix("-") {
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                } else if line.hasPrefix("@@") {
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.blue)
                } else {
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func labeledRow(label: String, value: String, icon: String, monospaced: Bool = false, selectable: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if selectable {
                    Text(value)
                        .font(monospaced ? .system(size: 12, design: .monospaced) : .callout)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                } else {
                    Text(value)
                        .font(monospaced ? .system(size: 12, design: .monospaced) : .callout)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private func loadDiff() async {
        isLoadingDiff = true
        defer { isLoadingDiff = false }
        do {
            let detail = try await GitHubService.shared.fetchCommitDetail(
                owner: owner, repo: repo, sha: commit.sha
            )
            guard let files = detail.files, !files.isEmpty else {
                diffContent = "No file changes in this commit."
                return
            }
            var lines: [String] = []
            for file in files {
                lines.append("File: \(file.filename) [\(file.status)] (+\(file.additions), -\(file.deletions))")
                if let patch = file.patch {
                    lines.append(patch)
                }
                lines.append("")
            }
            diffContent = lines.joined(separator: "\n")
        } catch {
            diffContent = "Failed to load diff: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Types

private struct CommitNotification: Equatable {
    let message: String
    let isError: Bool
}
