import SwiftUI

struct GitSidebarView: View {
    @Bindable var viewModel: GitViewModel

    var body: some View {
        VStack {
            if viewModel.isGitInstalled {
                List {
                    Section("Quick Links") {
                        NavigationLink(destination: GitBranchesView(viewModel: viewModel)) {
                            Label("Branches", systemImage: "arrow.triangle.pull")
                        }
                        NavigationLink(destination: GitHistoryView(viewModel: viewModel)) {
                            Label("History", systemImage: "clock")
                        }
                        NavigationLink(destination: GitChangesView(viewModel: viewModel)) {
                            Label("Changes", systemImage: "doc.on.doc")
                        }
                        NavigationLink(destination: GitCommitComposerView(viewModel: viewModel)) {
                            Label("Commit Composer", systemImage: "plus.square.on.square")
                        }
                        NavigationLink(destination: GitDiffView(viewModel: viewModel)) {
                            Label("Diff View", systemImage: "plus.forwardslash.minus")
                        }
                        NavigationLink(destination: GitPanelView(viewModel: viewModel)) {
                            Label("Git Panel", systemImage: "macwindow.on.rectangle")
                        }
                    }

                    Section("Changes") {
                        if viewModel.status.changedFiles.isEmpty {
                            Text("No changes")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.status.changedFiles, id: \.url) { file in
                                GitFileRowView(file: file)
                            }
                        }
                    }
                }

                VStack {
                    TextField("Commit message", text: $viewModel.commitMessage)
                        .textFieldStyle(.roundedBorder)

                    Button("Commit") {
                        Task { await viewModel.commit() }
                    }
                    .disabled(viewModel.commitMessage.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            } else {
                GitNotInstalledView()
            }
        }
    }
}
