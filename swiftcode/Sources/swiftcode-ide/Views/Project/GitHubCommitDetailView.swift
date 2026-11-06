// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/GitHub/Legacy/CommitHistoryView.swift — `CommitDetailView` only
//   (Legacy main ab03f681, lines 402-568)
//
// Destination: swiftcode-ide/Views/Project/GitHubCommitDetailView.swift.
//
// Adaptations (behaviour preserved unless noted):
// * Renamed `CommitDetailView` → `GitHubCommitDetailView`: production
//   already has a `CommitDetailView` in this module
//   (`SourceControlEditor.swift:449`) — a shell-model view taking
//   `detail:scm:model:colors:` for a *local* commit. That view cannot be
//   constructed from `(commit, owner, repo)` (it needs live workspace
//   shell models), so Legacy's GitHub-API detail view is ported under
//   its own name and the call site in `CommitHistoryView` is rebound to
//   it. The shell view is untouched.
// * `GitHubService.shared.fetchCommitDetail` and its
//   `GitHubCommitDetailResponse` / `GitHubCommitFile` types are ported in
//   `SwiftCodeGitHub` in this same wave; the view body is otherwise
//   verbatim (production `GitHubCommit` already exposes the nested
//   `commit.message` / `commit.author?.name/date` view this body reads).
// * Imports added: `SwiftCodeGitHub` (`GitHubCommit`,
//   `GitHubService`), `SwiftCodeUI` (`ModernGroupBoxStyle`).

import SwiftUI
import SwiftCodeGitHub
import SwiftCodeUI

struct GitHubCommitDetailView: View {
    let commit: GitHubCommit
    let owner: String
    let repo: String

    @State private var diffContent: String = ""
    @State private var isLoadingDiff = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Commit Details", systemImage: "tag.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(spacing: 20) {
                    // Card 1: Specs
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            labeledRow(label: "SHA Hash", value: commit.sha, icon: "tag", monospaced: true, selectable: true)
                            if let author = commit.commit.author {
                                if let name = author.name {
                                    labeledRow(label: "Author", value: name, icon: "person.circle")
                                }
                                if let date = author.date {
                                    labeledRow(label: "Date", value: date.formatted(date: .long, time: .shortened), icon: "calendar")
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Message
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Commit Message")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(commit.commit.message)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Diff Preview
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Diff Preview", systemImage: "doc.text.magnifyingglass")
                                    .font(.subheadline.bold())
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
                }
            }
        }
        .padding(24)
        .frame(minWidth: 550, minHeight: 400)
        .task { await loadDiff() }
    }

    private var diffView: some View {
        VStack(alignment: .leading, spacing: 2) {
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
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                if selectable {
                    Text(value)
                        .font(monospaced ? .system(size: 11, design: .monospaced) : .callout)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                } else {
                    Text(value)
                        .font(monospaced ? .system(size: 11, design: .monospaced) : .callout)
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
