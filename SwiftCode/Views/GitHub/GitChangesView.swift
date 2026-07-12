import SwiftUI

struct GitChangesView: View {
    @State var viewModel: GitViewModel
    @State private var commitMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Card 1: Action Controls Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Git Workspace Actions", systemImage: "arrow.clockwise")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Button(action: { Task { await viewModel.refreshStatus() } }) {
                                Label("Refresh Status", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Stage All Files") {
                                if let status = viewModel.status {
                                    let unstaged = status.files.filter { !$0.isStaged }
                                    for file in unstaged {
                                        Task { await viewModel.stage(file) }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)

                            Button("Unstage All Files") {
                                if let status = viewModel.status {
                                    let staged = status.files.filter { $0.isStaged }
                                    for file in staged {
                                        Task { await viewModel.unstage(file) }
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                if let status = viewModel.status {
                    // Card 2: Staged Changes Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Staged Changes", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                                Text("\(status.files.filter { $0.isStaged }.count) files")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }

                            let staged = status.files.filter { $0.isStaged }
                            if staged.isEmpty {
                                Text("No staged changes. Stage files below to prepare for commit.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(staged) { file in
                                        HStack {
                                            GitFileRowView(file: file)
                                            Spacer()
                                            Button("Unstage") {
                                                Task { await viewModel.unstage(file) }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.04))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Unstaged Changes Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Unstaged Changes", systemImage: "exclamationmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                                Text("\(status.files.filter { !$0.isStaged }.count) files")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }

                            let unstaged = status.files.filter { !$0.isStaged }
                            if unstaged.isEmpty {
                                Text("No unstaged changes in the working tree.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(unstaged) { file in
                                        HStack {
                                            GitFileRowView(file: file)
                                            Spacer()
                                            Button("Stage") {
                                                Task { await viewModel.stage(file) }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                        }
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.04))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Directly embed GitCommitComposerView without outer double nesting
                GitCommitComposerView(message: $commitMessage) {
                    Task {
                        guard let url = viewModel.repositoryURL else { return }
                        try? await GitService.shared.commit(message: commitMessage, repositoryURL: url)
                        commitMessage = ""
                        await viewModel.refreshStatus()
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}
