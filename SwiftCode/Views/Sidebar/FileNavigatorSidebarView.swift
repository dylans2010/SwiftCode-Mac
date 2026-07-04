import SwiftUI

struct FileNavigatorSidebarView: View {
    @Bindable var viewModel: ProjectTreeViewModel
    @State private var showingRenameSheet = false
    @State private var selectedNodeForRename: ProjectNode?

    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    Task {
                        guard let projectURL = viewModel.projectURL else { return }
                        let newFileURL = projectURL.appendingPathComponent("Untitled.swift")
                        try? await FileSystemService.shared.createFile(at: newFileURL)
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "plus")
                }
                .help("New File")
                .disabled(viewModel.projectURL == nil)

                Button(action: {
                    Task {
                        guard let projectURL = viewModel.projectURL else { return }
                        let newFolderURL = projectURL.appendingPathComponent("New Folder")
                        try? await FileSystemService.shared.createDirectory(at: newFolderURL)
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Folder")
                .disabled(viewModel.projectURL == nil)

                Spacer()

                Button(action: {
                    Task {
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(.horizontal)
            .padding(.top, 4)

            List {
                if let rootNode = viewModel.rootNode {
                    OutlineGroup(rootNode, children: \.children) { node in
                        ProjectTreeRowView(node: node)
                            .contextMenu {
                                Button("Rename...") {
                                    selectedNodeForRename = node
                                    showingRenameSheet = true
                                }

                                Button("Delete", role: .destructive) {
                                    Task {
                                        try? await FileSystemService.shared.delete(at: node.url)
                                        await viewModel.refresh()
                                    }
                                }
                            }
                    }
                } else {
                    Text("No project open")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
