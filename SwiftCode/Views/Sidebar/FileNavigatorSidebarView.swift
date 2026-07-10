import SwiftUI

// MARK: - FileSymbolsShow (Central symbol registry)

public struct FileSymbolsShow {
    public static func symbol(forPathExtension ext: String, isFolder: Bool = false) -> String {
        if isFolder {
            return "folder.fill"
        }

        let cleaned = ext.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch cleaned {
        case "swift":
            return "swift"
        case "md":
            return "doc.text.fill"
        case "txt":
            return "doc.text.fill"
        case "json":
            return "curlybraces.square.fill"
        case "xml":
            return "chevron.left.forwardslash.chevron.right"
        case "yml", "yaml":
            return "gearshape.2.fill"
        case "js", "ts", "jsx", "tsx":
            return "chevron.left.forwardslash.chevron.right"
        case "css":
            return "paintbrush.fill"
        case "html":
            return "globe"
        case "xcodeproj":
            return "hammer.circle.fill"
        case "pbxproj":
            return "shippingbox.fill"
        case "plist":
            return "list.bullet.rectangle.fill"
        case "entitlements":
            return "lock.shield.fill"
        case "gitignore":
            return "eye.slash.fill"
        case "swiftpm", "package":
            return "shippingbox.fill"
        case "zip":
            return "archivebox.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "png", "jpg", "jpeg":
            return "photo.fill"
        case "svg":
            return "photo.artframe"
        case "mov", "mp4":
            return "film.fill"
        case "mp3":
            return "music.note"
        case "wav":
            return "waveform"
        default:
            if cleaned.hasPrefix(".") {
                return "eye.slash"
            }
            return "doc.fill"
        }
    }
}

// MARK: - Reusable Trackpad Double Click Interaction Modifier

struct FileDoubleClickHandlerModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 2) {
                action()
            }
    }
}

extension View {
    func onFileDoubleClick(perform action: @escaping () -> Void) -> some View {
        self.modifier(FileDoubleClickHandlerModifier(action: action))
    }
}

// MARK: - FileNavigatorSidebarView

struct FileNavigatorSidebarView: View {
    @Bindable var viewModel: ProjectTreeViewModel
    @Environment(WorkspaceViewModel.self) var workspaceViewModel

    @State private var showingRenameSheet = false
    @State private var selectedNodeForRename: ProjectNode?
    @State private var renameText = ""

    @State private var showingDeleteConfirm = false
    @State private var selectedNodeForDelete: ProjectNode?

    @State private var selectedNodeForWorkflow: ProjectNode?
    @State private var showingWorkflowPopover = false

    var body: some View {
        VStack(spacing: 0) {
            // Liquid Glass Styled Header Actions
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        guard let projectURL = viewModel.projectURL else { return }
                        let newFileURL = projectURL.appendingPathComponent("Untitled.swift")
                        try? await FileSystemService.shared.createFile(at: newFileURL)
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.plain)
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
                        .font(.subheadline.bold())
                }
                .buttonStyle(.plain)
                .help("New Folder")
                .disabled(viewModel.projectURL == nil)

                Spacer()

                Button(action: {
                    Task {
                        await viewModel.refresh()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(
                Divider(), alignment: .bottom
            )

            // Modern Navigation List
            List(selection: $viewModel.selectedNodeID) {
                if let error = viewModel.loadError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding()
                }

                if let rootNode = viewModel.rootNode {
                    // Start with the root children to avoid showing the project root itself in the list
                    ProjectTreeNodeView(
                        node: rootNode,
                        viewModel: viewModel,
                        onRename: { node in
                            selectedNodeForRename = node
                            renameText = node.url.lastPathComponent
                            showingRenameSheet = true
                        },
                        onDelete: { node in
                            selectedNodeForDelete = node
                            showingDeleteConfirm = true
                        },
                        onDoubleClick: { node in
                            selectedNodeForWorkflow = node
                            showingWorkflowPopover = true
                        }
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No active project")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                }
            }
            .listStyle(.sidebar)
        }
        .onChange(of: viewModel.selectedNodeID) { oldValue, newValue in
            workspaceViewModel.handleFileSelectionChange(nodeID: newValue)
        }
        // Rename Dialog Popover/Sheet
        .sheet(isPresented: $showingRenameSheet) {
            NavigationStack {
                VStack(spacing: 16) {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                .padding()
                .navigationTitle("Rename Item")
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
            .frame(width: 300, height: 160)
        }
        // Delete Confirmation Dialog
        .confirmationDialog(
            "Delete \(selectedNodeForDelete?.url.lastPathComponent ?? "")?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let node = selectedNodeForDelete {
                    Task {
                        try? await FileSystemService.shared.delete(at: node.url)
                        await viewModel.refresh()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. The file or folder will be removed permanently from disk.")
        }
        // Double Click Workflow Popover
        .popover(isPresented: $showingWorkflowPopover, attachmentAnchor: .rect(.bounds)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedNodeForWorkflow?.url.lastPathComponent ?? "File Actions")
                    .font(.headline)
                    .foregroundColor(.primary)

                Divider()

                Button {
                    showingWorkflowPopover = false
                    if let node = selectedNodeForWorkflow {
                        selectedNodeForRename = node
                        renameText = node.url.lastPathComponent
                        showingRenameSheet = true
                    }
                } label: {
                    Label("Rename...", systemImage: "pencil")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showingWorkflowPopover = false
                    if let node = selectedNodeForWorkflow {
                        selectedNodeForDelete = node
                        showingDeleteConfirm = true
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 220)
        }
    }
}

// MARK: - ProjectTreeNodeView

struct ProjectTreeNodeView: View {
    let node: ProjectNode
    @Bindable var viewModel: ProjectTreeViewModel
    let onRename: (ProjectNode) -> Void
    let onDelete: (ProjectNode) -> Void
    let onDoubleClick: (ProjectNode) -> Void
    @State private var isExpanded: Bool = false

    var body: some View {
        if node.kind == .folder {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        ProjectTreeNodeView(
                            node: child,
                            viewModel: viewModel,
                            onRename: onRename,
                            onDelete: onDelete,
                            onDoubleClick: onDoubleClick
                        )
                    }
                } else if isExpanded {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding(.leading, 8)
                }
            } label: {
                nodeRowContent
            }
            .onChange(of: isExpanded) { oldValue, newValue in
                if newValue && node.children == nil {
                    Task {
                        await viewModel.toggleExpanded(node)
                    }
                }
            }
        } else {
            nodeRowContent
        }
    }

    private var nodeRowContent: some View {
        HStack(spacing: 8) {
            Image(systemName: FileSymbolsShow.symbol(forPathExtension: node.url.pathExtension, isFolder: node.kind == .folder))
                .foregroundStyle(node.kind == .folder ? .blue : .orange)
                .font(.subheadline)
                .frame(width: 16)

            Text(node.url.lastPathComponent)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onFileDoubleClick {
            onDoubleClick(node)
        }
        .contextMenu {
            Button("Rename...") {
                onRename(node)
            }

            Button("Delete", role: .destructive) {
                onDelete(node)
            }
        }
        .tag(node.url.path)
    }
}
