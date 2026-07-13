import SwiftUI

@MainActor
struct CommitsView: View {
    var gitViewModel: GitViewModel
    @State private var selectedCommit: GitCommit?

    // Rollback operations state
    @State private var isRunningGitAction = false
    @State private var gitActionProgress = ""
    @State private var gitActionLog = ""
    @State private var showRollbackSuccess = false
    @State private var hasPushed = false

    var body: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack(spacing: 12) {
                Label("Commit History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(.purple)

                Spacer()

                Button {
                    Task {
                        await gitViewModel.refreshStatus()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if gitViewModel.history.isEmpty {
                GitHubEmptyStateView(
                    title: "No Commits Recorded",
                    description: "This branch has no commits recorded in Git timeline history.",
                    systemImage: "clock",
                    accentColor: .purple
                )
            } else {
                List(gitViewModel.history) { commit in
                    Button {
                        selectedCommit = commit
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.purple)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(commit.subject)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("\(commit.author) • \(commit.dateString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(String(commit.sha.prefix(7)))
                                .font(.system(.caption2, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .foregroundStyle(.primary)
                                .cornerRadius(4)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
        .sheet(item: $selectedCommit) { commit in
            commitDetailSheet(commit)
        }
    }

    private func commitDetailSheet(_ commit: GitCommit) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("Commit Details & Rollback", systemImage: "clock.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                Button("Done") {
                    selectedCommit = nil
                }
                .buttonStyle(.bordered)
                .disabled(isRunningGitAction)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Commit metadata
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(commit.subject)
                                .font(.title3.bold())

                            HStack(spacing: 8) {
                                Text(String(commit.sha.prefix(7)))
                                    .font(.system(.caption2, design: .monospaced).bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.12))
                                    .foregroundStyle(.purple)
                                    .cornerRadius(4)

                                Text("\(commit.author) • \(commit.dateString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    if !commit.body.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Commit Body")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)

                                Text(commit.body)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Git Rollback and Push card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Production Rollback Actions", systemImage: "arrow.uturn.backward.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.red)

                            Divider()

                            Text("Rollback will execute 'git reset --hard \(String(commit.sha.prefix(7)))'. This permanently discards all uncommitted working directory changes and resets the branch history to this commit point.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                Button(role: .destructive) {
                                    runRollback(sha: commit.sha)
                                } label: {
                                    if isRunningGitAction && gitActionProgress.contains("Resetting") {
                                        ProgressView().controlSize(.small).padding(.horizontal, 4)
                                    } else {
                                        Label("Execute Rollback", systemImage: "arrow.counterclockwise.circle.fill")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .disabled(isRunningGitAction)

                                if showRollbackSuccess {
                                    Button {
                                        runForcePush()
                                    } label: {
                                        if isRunningGitAction && gitActionProgress.contains("Pushing") {
                                            ProgressView().controlSize(.small).padding(.horizontal, 4)
                                        } else {
                                            Label("Force-Push to Remote", systemImage: "cloud.heavyrain.fill")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .disabled(isRunningGitAction || hasPushed)
                                    .help("Required if the commit has already been pushed to GitHub.")
                                }
                            }

                            if showRollbackSuccess {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Rollback Successful!", systemImage: "checkmark.circle.fill")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.green)
                                    Text("Please review local files to ensure changes are correct. If this branch is tracked remotely, you may need to force-push to overwrite remote history.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            }

                            if isRunningGitAction {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text(gitActionProgress)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if !gitActionLog.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Git Terminal Output:")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.secondary)
                                    ScrollView {
                                        Text(gitActionLog)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                    }
                                    .frame(height: 80)
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
        }
        .frame(width: 580, height: 560)
        .onDisappear {
            // Reset states on dismiss
            showRollbackSuccess = false
            hasPushed = false
            gitActionLog = ""
            gitActionProgress = ""
        }
    }

    private func runRollback(sha: String) {
        isRunningGitAction = true
        gitActionProgress = "Resetting repository hard to \(String(sha.prefix(7)))..."
        gitActionLog = ""

        Task {
            do {
                try await gitViewModel.rollback(to: sha)
                gitActionLog = "git reset --hard \(sha)\nHEAD is now at \(String(sha.prefix(7)))"
                gitActionProgress = "Rollback completed."
                showRollbackSuccess = true
            } catch {
                gitActionLog = "Error resetting branch to \(sha):\n\(error.localizedDescription)"
                gitActionProgress = "Rollback failed."
            }
            isRunningGitAction = false
            await gitViewModel.refreshStatus()
        }
    }

    private func runForcePush() {
        guard let branchName = gitViewModel.status?.branchName else { return }

        isRunningGitAction = true
        gitActionProgress = "Force-pushing local state to branch '\(branchName)' on origin..."
        gitActionLog = ""

        Task {
            do {
                try await gitViewModel.forcePush(branch: branchName)
                gitActionLog = "git push origin \(branchName) --force\nSuccess: Remote branch overwritten."
                gitActionProgress = "Force-push completed."
                hasPushed = true
            } catch {
                gitActionLog = "Error force-pushing to origin/\(branchName):\n\(error.localizedDescription)"
                gitActionProgress = "Force-push failed."
            }
            isRunningGitAction = false
            await gitViewModel.refreshStatus()
        }
    }
}
