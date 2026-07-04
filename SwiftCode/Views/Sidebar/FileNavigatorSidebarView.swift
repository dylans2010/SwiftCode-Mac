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
                        let newFileURL = viewModel.projectURL.appendingPathComponent("Untitled.swift")
                        try? await FileSystemService.shared.createFile(at: newFileURL)
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "plus")
                }
                .help("New File")

                Button(action: {
                    Task {
                        let newFolderURL = viewModel.projectURL.appendingPathComponent("New Folder")
                        try? await FileSystemService.shared.createDirectory(at: newFolderURL)
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Folder")

                Spacer()

                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(.horizontal)
            .padding(.top, 4)

            List(viewModel.rootNodes, children: \.children) { node in
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
        }
    }
}
