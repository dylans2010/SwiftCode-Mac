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
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading && commits.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Loading Commits…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = errorMessage, commits.isEmpty {
                        errorView(error)
                    } else if commits.isEmpty {
                        emptyView
                    } else {
                        // Card 1: Branch Metadata Overview
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Active Branch History", systemImage: "clock.arrow.circlepath")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Spacer()
                                    Text(currentBranch)
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                }

                                Text("Showing the latest \(commits.count) commits for the active branch. You can review detailed file diffs, revert, or amend commits.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 2: Timeline Directory
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Commits Timeline", systemImage: "list.bullet")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                    Spacer()
                                }

                                ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                                    commitRow(commit: commit, index: index)
                                    if commit.id != commits.last?.id {
                                        Divider().opacity(0.3)
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .navigationTitle("Commit History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem {
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
        .task { await loadHistory() }
        .onChange(of: currentBranch) {
            Task { await loadHistory() }
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
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 6) {
                Text(commit.commit.message.components(separatedBy: "\n").first ?? commit.commit.message)
                    .font(.callout.bold())
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
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                    if index == 0 {
                        Text("HEAD")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }

                // Action buttons
                HStack(spacing: 8) {
                    actionChip(label: "Diff", icon: "doc.text.magnifyingglass", color: .blue) {
                        showDiffPreview = commit
                        selectedCommit = commit
                    }

                    if index == 0 {
                        actionChip(label: "Amend", icon: "pencil", color: .yellow) {
                            amendTarget = commit
                            amendMessage = commit.commit.message
                            showAmendSheet = true
                        }
                    }

                    actionChip(label: "Revert", icon: "arrow.uturn.backward", color: .red) {
                        Task { await revertCommit(commit) }
                    }

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
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
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
            ScrollView {
                VStack(spacing: 24) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Amend Last Commit", systemImage: "pencil.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            Text("Edit commit message for HEAD:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $amendMessage)
                                .font(.body)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                .frame(minHeight: 120)

                            Text("Note: Amending rewrites the last commit. Avoid amending commits already pushed to a shared branch.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Amend Commit")
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
    }

    // MARK: - Empty / Error Views

    private var emptyView: some View {
        GroupBox {
            VStack(spacing: 16) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange.opacity(0.5))
                Text("No Commits Found")
                    .font(.headline)
                Text("Branch \(currentBranch) has no commit history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func errorView(_ message: String) -> some View {
        GroupBox {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.red.opacity(0.7))
                Text("Failed to Load History")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await loadHistory() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    // MARK: - Notification Banner

    private func commitNotificationBanner(_ n: CommitNotification) -> some View {
        HStack(spacing: 10) {
            Image(systemName: n.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(n.isError ? .red : .green)
            Text(n.message)
                .font(.subheadline)
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

        let hasConflict = false
        if hasConflict {
            conflictDetails = "Conflict while reverting \(commit.commit.message). Manual resolution required."
            showConflictAlert = true
            return
        }

        try? await Task.sleep(nanoseconds: 800_000_000)
        showNotification("Revert of \(String(commit.sha.prefix(8))) created (placeholder)", isError: false)
        await loadHistory()
    }

    private func cherryPick(_ commit: GitHubCommit) async {
        isOperating = true
        defer { isOperating = false }

        let hasConflict = false
        if hasConflict {
            conflictDetails = "Conflict cherry-picking \(commit.commit.message) onto \(currentBranch). Manual resolution required."
            showConflictAlert = true
            return
        }

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
                VStack(spacing: 24) {
                    // Card 1: SHA and Metadata
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Commit Specifications", systemImage: "tag")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            labeledRow(label: "SHA", value: commit.sha, icon: "tag", monospaced: true, selectable: true)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Message
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Commit Message", systemImage: "pencil.and.outline")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                            Text(commit.commit.message)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Author & Date
                    if let author = commit.commit.author {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Author Details", systemImage: "person.circle")
                                        .font(.headline)
                                        .foregroundColor(.purple)
                                    Spacer()
                                }
                                if let name = author.name {
                                    labeledRow(label: "Author", value: name, icon: "person.circle")
                                }
                                if let date = author.date {
                                    labeledRow(label: "Date", value: date.formatted(date: .long, time: .shortened), icon: "calendar")
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Card 4: Diff Preview
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Diff Preview", systemImage: "doc.text.magnifyingglass")
                                    .font(.headline)
                                    .foregroundColor(.green)
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
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // View on GitHub
                    if let urlStr = commit.htmlUrl, let url = URL(string: urlStr) {
                        GroupBox {
                            Link(destination: url) {
                                Label("View On GitHub", systemImage: "safari")
                                    .font(.callout)
                                    .foregroundColor(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Commit Details")
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

    private func labeledRow(label: String, value: String, icon: String, monospaced: Bool = false, selectable: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
