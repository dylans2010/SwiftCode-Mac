import SwiftUI

@MainActor
struct GitChangesView: View {
    @State var viewModel: GitViewModel
    @State private var commitMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Git Workspace Changes", systemImage: "plus.minus.circle")
                    .font(.headline)
                    .foregroundColor(.orange)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { Task { await viewModel.refreshStatus() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button("Stage All") {
                        if let status = viewModel.status {
                            let unstaged = status.files.filter { !$0.isStaged }
                            for file in unstaged {
                                Task { await viewModel.stage(file) }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button("Unstage All") {
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
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    if let status = viewModel.status {
                        // Card 1: Staged Changes Card
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Staged Changes", systemImage: "checkmark.circle.fill")
                                        .font(.subheadline.bold())
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
                                            .padding(6)
                                            .background(Color.secondary.opacity(0.04))
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 2: Unstaged Changes Card
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Unstaged Changes", systemImage: "exclamationmark.circle.fill")
                                        .font(.subheadline.bold())
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
                                            .padding(6)
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

                    // Card 3: Commit Composer
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Commit Changes", systemImage: "pencil.and.outline")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)

                            TextEditor(text: $commitMessage)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 100)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )

                            Button("Commit to Local Branch") {
                                Task {
                                    guard let url = viewModel.repositoryURL else { return }
                                    try? await GitService.shared.commit(message: commitMessage, repositoryURL: url)
                                    commitMessage = ""
                                    await viewModel.refreshStatus()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.large)
                            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
        }
        .sourceControlEmbedded()
    }
}
