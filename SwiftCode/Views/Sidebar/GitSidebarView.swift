import SwiftUI

struct GitSidebarView: View {
    @Bindable var viewModel: GitViewModel
    @State private var commitMessage = ""

    var body: some View {
        VStack {
            if viewModel.isGitInstalled {
                List {
                    Section("Quick Links") {
                        NavigationLink(destination: GitChangesView(viewModel: viewModel)) {
                            Label("Changes", systemImage: "doc.on.doc")
                        }
                        NavigationLink(destination: GitHistoryView(commits: viewModel.history)) {
                            Label("History", systemImage: "clock")
                        }
                        NavigationLink(destination: GitBranchesView(branches: viewModel.branches)) {
                            Label("Branches", systemImage: "arrow.triangle.pull")
                        }
                        NavigationLink(destination: GitPanelView(viewModel: viewModel)) {
                            Label("Git Panel", systemImage: "macwindow.on.rectangle")
                        }
                    }

                    Section("Changes") {
                        if let status = viewModel.status {
                            if status.files.isEmpty {
                                Text("No changes")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(status.files) { file in
                                    GitFileRowView(file: file)
                                }
                            }
                        } else {
                            Text("No changes")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack {
                    GitCommitComposerView(message: $commitMessage, gitViewModel: viewModel) {
                        Task {
                            guard let url = viewModel.repositoryURL else { return }
                            try? await GitService.shared.commit(message: commitMessage, repositoryURL: url)
                            commitMessage = ""
                            await viewModel.refreshStatus()
                        }
                    }
                }
                .padding()
            } else {
                GitNotInstalledView()
            }
        }
    }
}
