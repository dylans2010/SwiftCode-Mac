import SwiftUI

@MainActor
struct CommitsView: View {
    var gitViewModel: GitViewModel
    @State private var selectedCommit: GitCommit?

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
                Label("Commit Details", systemImage: "clock.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                Button("Done") {
                    selectedCommit = nil
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 420)
    }
}
