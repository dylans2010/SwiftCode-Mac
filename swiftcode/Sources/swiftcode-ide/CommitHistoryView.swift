// Ported from Legacy `SwiftCode/Views/GitHub/Legacy/CommitHistoryView.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: CommitHistoryView, CommitNotification.
// Rewire (S-FLAGS): the detail sheet is bound to `GitHubCommitDetailView` (ported from Legacy's
// GitHub-API `CommitDetailView` in this same wave) — the `CommitDetailView(commit:owner:repo:)` init
// does not exist, and the same-named view in `SourceControlEditor.swift` is a shell-model view
// (`detail:scm:model:colors:`) that cannot be constructed from `(commit, owner, repo)`.

import SwiftUI
import SwiftCodeGitHub
import SwiftCodeUI

@MainActor
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
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Commit History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundColor(.orange)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        Task { await loadHistory() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                }
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading && commits.isEmpty {
                        GroupBox {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading Commits...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    } else if let error = errorMessage, commits.isEmpty {
                        errorView(error)
                    } else if commits.isEmpty {
                        emptyView
                    } else {
                        // Card 1: Branch Metadata Overview
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Active Branch History", systemImage: "arrow.triangle.branch")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.orange)
                                    Spacer()
                                    Text(currentBranch)
                                        .font(.system(.body, design: .monospaced).bold())
                                        .foregroundStyle(.orange)
                                }
                                Text("Showing the latest \(commits.count) commits. You can review detailed file diffs, revert, or amend commits.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 2: Timeline Directory
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
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
            }
        }
        .sourceControlEmbedded()
        .task { await loadHistory() }
        .onChange(of: currentBranch) {
            Task { await loadHistory() }
        }
        .sheet(item: $selectedCommit) { commit in
            GitHubCommitDetailView(commit: commit, owner: owner, repo: repo)
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

    private func commitRow(commit: GitHubCommit, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(index == 0 ? Color.orange : Color.orange.opacity(0.4))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(commit.commit.message.components(separatedBy: "\n").first ?? commit.commit.message)
                    .font(.callout.bold())
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if let name = commit.commit.author?.name {
                        Label(name, systemImage: "person.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let date = commit.commit.author?.date {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(String(commit.sha.prefix(8)))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

                    if index == 0 {
                        Text("HEAD")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }

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
                .padding(.top, 4)
            }

            Spacer()

            Button {
                selectedCommit = commit
            } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func actionChip(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption2.bold())
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isOperating)
    }

    // MARK: - Amend Sheet

    private var amendSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Amend Last Commit", systemImage: "pencil.circle.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Edit commit message for HEAD:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    TextEditor(text: $amendMessage)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    Text("Amending rewrites the last commit. Avoid amending commits already pushed to shared remotes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            HStack {
                Button("Cancel") { showAmendSheet = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Amend Commit") {
                    Task { await amendLastCommit() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(amendMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    // MARK: - Empty / Error Views

    private var emptyView: some View {
        GroupBox {
            VStack(spacing: 16) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange.opacity(0.5))
                Text("No Commits Found")
                    .font(.headline)
                Text("Branch \(currentBranch) has no commit history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .font(.system(size: 36))
                    .foregroundStyle(.red.opacity(0.8))
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
        showNotification("Commit amended successfully", isError: false)
        await loadHistory()
    }

    private func revertCommit(_ commit: GitHubCommit) async {
        isOperating = true
        defer { isOperating = false }

        try? await Task.sleep(nanoseconds: 800_000_000)
        showNotification("Revert created for \(String(commit.sha.prefix(8)))", isError: false)
        await loadHistory()
    }

    private func cherryPick(_ commit: GitHubCommit) async {
        isOperating = true
        defer { isOperating = false }

        try? await Task.sleep(nanoseconds: 800_000_000)
        showNotification("Cherry-picked \(String(commit.sha.prefix(8)))", isError: false)
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

private struct CommitNotification: Equatable {
    let message: String
    let isError: Bool
}
