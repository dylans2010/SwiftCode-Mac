import SwiftUI

struct GitChangesView: View {
    @State var viewModel: GitViewModel
    @State private var commitMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                if let status = viewModel.status {
                    Section("Staged Changes") {
                        ForEach(status.files.filter { $0.isStaged }) { file in
                            GitFileRowView(file: file)
                                .contextMenu {
                                    Button("Unstage") { Task { await viewModel.unstage(file) } }
                                }
                        }
                    }
                    Section("Unstaged Changes") {
                        ForEach(status.files.filter { !$0.isStaged }) { file in
                            GitFileRowView(file: file)
                                .contextMenu {
                                    Button("Stage") { Task { await viewModel.stage(file) } }
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
