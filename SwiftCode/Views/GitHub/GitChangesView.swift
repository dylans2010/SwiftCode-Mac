import SwiftUI

struct GitChangesView: View {
    @State var viewModel: GitViewModel
    @State private var commitMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { Task { await viewModel.refreshStatus() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Spacer()
                Button("Stage All") {
                     // Stage all logic
                }
                Button("Unstage All") {
                    // Unstage all logic
                }
            }
            .padding(8)
            .buttonStyle(.plain)

            List {
                if let status = viewModel.status {
                    Section("Staged Changes") {
                        ForEach(status.files.filter { $0.isStaged }) { file in
                            GitFileRowView(file: file)
                                .contextMenu {
                                    Button("Unstage") { Task { await viewModel.unstage(file) } }
                                    Button("Discard Changes") { /* Discard */ }
                                }
                        }
                    }
                    Section("Unstaged Changes") {
                        ForEach(status.files.filter { !$0.isStaged }) { file in
                            GitFileRowView(file: file)
                                .contextMenu {
                                    Button("Stage") { Task { await viewModel.stage(file) } }
                                    Button("Stage Individual Hunks") { /* Hunk staging */ }
                                    Button("Discard Changes") { /* Discard */ }
                                }
                        }
                    }
                }
            }

            GitCommitComposerView(message: $commitMessage) {
                Task {
                    guard let url = viewModel.repositoryURL else { return }
                    try? await GitService.shared.commit(message: commitMessage, repositoryURL: url)
                    commitMessage = ""
                    await viewModel.refreshStatus()
                }
            }
        }
    }
}
