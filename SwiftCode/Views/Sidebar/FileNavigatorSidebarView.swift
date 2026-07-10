import SwiftUI

struct FileNavigatorSidebarView: View {
    @Bindable var viewModel: ProjectTreeViewModel
    @Environment(WorkspaceViewModel.self) var workspaceViewModel
    @State private var showingRenameSheet = false
    @State private var selectedNodeForRename: ProjectNode?
    @State private var renameText = ""

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

            List(selection: $viewModel.selectedNodeID) {
                if let error = viewModel.loadError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding()
                }

                if let rootNode = viewModel.rootNode {
                    // Start with the root children to avoid showing the project root itself in the list
                    // but since the current structure shows rootNode, we keep it but fix the recursive rendering
                    ProjectTreeNodeView(node: rootNode, viewModel: viewModel) { node in
                        selectedNodeForRename = node
                        renameText = node.url.lastPathComponent
                        showingRenameSheet = true
                    }
                } else {
                    Text("No project open")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: viewModel.selectedNodeID) { oldValue, newValue in
            workspaceViewModel.handleFileSelectionChange(nodeID: newValue)
        }
        .sheet(isPresented: $showingRenameSheet) {
            NavigationStack {
                VStack {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
                .navigationTitle("Rename")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingRenameSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Rename") {
                            if let node = selectedNodeForRename {
                                Task {
                                    let newURL = node.url.deletingLastPathComponent().appendingPathComponent(renameText)
                                    try? FileManager.default.moveItem(at: node.url, to: newURL)
                                    await viewModel.refresh()
                                    showingRenameSheet = false
                                }
                            }
                        }
                        .disabled(renameText.isEmpty)
                    }
                }
            }
            .frame(width: 300, height: 150)
        }
    }
}

struct ProjectTreeNodeView: View {
    let node: ProjectNode
    @Bindable var viewModel: ProjectTreeViewModel
    let onRename: (ProjectNode) -> Void
    @State private var isExpanded: Bool = false

    var body: some View {
        if node.kind == .folder {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        ProjectTreeNodeView(node: child, viewModel: viewModel, onRename: onRename)
                    }
                } else if isExpanded {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            } label: {
                ProjectTreeRowView(node: node)
                    .tag(node.url.path)
                    .contextMenu {
                        treeContextMenu(for: node)
                    }
            }
            .onChange(of: isExpanded) { oldValue, newValue in
                if newValue && node.children == nil {
                    Task {
                        await viewModel.toggleExpanded(node)
                    }
                }
            }
        } else {
            ProjectTreeRowView(node: node)
                .tag(node.url.path)
                .contextMenu {
                    treeContextMenu(for: node)
                }
        }
    }

    @ViewBuilder
    private func treeContextMenu(for node: ProjectNode) -> some View {
        Button("Rename...") {
            onRename(node)
        }

        Button("Delete", role: .destructive) {
            Task {
                try? await FileSystemService.shared.delete(at: node.url)
                await viewModel.refresh()
            }
        }
    }
}
