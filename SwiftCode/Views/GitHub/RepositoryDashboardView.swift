import SwiftUI

@MainActor
struct RepositoryDashboardView: View {
    var gitViewModel: GitViewModel
    let project: Project?
    var onNavigateToSection: (GitHubSidebarItem) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Welcome and Repo Details Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Repository Dashboard", systemImage: "square.grid.2x2.fill")
                                .font(.title2.bold())
                                .foregroundStyle(.blue)

                            Spacer()

                            if let repoName = project?.githubRepo, !repoName.isEmpty {
                                Text("Connected to Remote")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            } else {
                                Text("Local Only")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(project?.name ?? "No Project Selected")
                            .font(.title3.bold())

                        if let repo = project?.githubRepo, !repo.isEmpty {
                            Text("GitHub Reference: \(repo)")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Initialize a GitHub remote to enable pushing, pulling, pull requests, issues, and Actions workflows.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Dynamic Status & Statistics Grid
                let columns = [
                    GridItem(.adaptive(minimum: 220), spacing: 16)
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    // Local Branch card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Current Branch", systemImage: "arrow.triangle.branch")
                                .font(.headline)
                                .foregroundStyle(.orange)

                            Text(gitViewModel.status?.branchName ?? "main")
                                .font(.title3.bold())
                                .lineLimit(1)

                            Button("Manage Branches") {
                                onNavigateToSection(.branches)
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.orange)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Working Changes card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Working Directory", systemImage: "doc.text.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            let changedCount = gitViewModel.status?.files.count ?? 0
                            Text("\(changedCount) Modified Files")
                                .font(.title3.bold())

                            Button("View Changes") {
                                onNavigateToSection(.repositories) // Navigates back to Repo / Local Changes tab
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.blue)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Commits count / Sync card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Commit History", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                                .foregroundStyle(.purple)

                            let commitCount = gitViewModel.history.count
                            Text("\(commitCount) Local Commits")
                                .font(.title3.bold())

                            Button("History Timeline") {
                                onNavigateToSection(.commits)
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.purple)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Remote Synced Card (Ahead / Behind)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Remote Synchronization", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .foregroundStyle(.green)

                            let ahead = gitViewModel.status?.ahead ?? 0
                            let behind = gitViewModel.status?.behind ?? 0
                            Text("\(ahead) Ahead / \(behind) Behind")
                                .font(.title3.bold())

                            Button("Check Actions") {
                                onNavigateToSection(.actions)
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.green)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Recent Commits Subsection
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Recent Commits", systemImage: "list.dash")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        if gitViewModel.history.isEmpty {
                            Text("No commits recorded yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(gitViewModel.history.prefix(5)) { commit in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(commit.subject)
                                                .font(.subheadline.bold())
                                            Text("\(commit.author) • \(commit.dateString)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(String(commit.sha.prefix(7)))
                                            .font(.system(.caption2, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                    .padding(.vertical, 8)

                                    if commit.id != gitViewModel.history.prefix(5).last?.id {
                                        Divider()
                                    }
                                }
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
}
