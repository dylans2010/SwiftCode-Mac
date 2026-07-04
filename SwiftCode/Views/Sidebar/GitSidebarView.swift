import SwiftUI

struct GitSidebarView: View {
    @Bindable var viewModel: GitViewModel

    var body: some View {
        VStack {
            if viewModel.isGitInstalled {
                List {
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

                    Section("Branches") {
                        ForEach(viewModel.branches) { branch in
                            HStack {
                                Image(systemName: "arrow.triangle.pull")
                                Text(branch.name)
                                if branch.isCurrent {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accent)
                                }
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
