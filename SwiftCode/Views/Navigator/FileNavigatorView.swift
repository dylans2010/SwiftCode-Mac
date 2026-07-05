import SwiftUI

struct FileNavigatorView: View {
    let project: Project
    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var settings: AppSettings
    @State private var searchText = ""
    @State private var showNewFileDialog = false
    @State private var showNewFolderDialog = false
    @State private var newItemName = ""
    @State private var targetDirectory: String?
    @State private var showRenameDialog = false
    @State private var nodeToRename: FileNode?
    @State private var renameText = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isCreatingFolder = false

    var filteredFiles: [FileNode] {
        if searchText.isEmpty { return project.files }
        return filterNodes(project.files, query: searchText.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Files")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    isCreatingFolder = false
                    targetDirectory = nil
                    newItemName = ""
                    showNewFileDialog = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    isCreatingFolder = true
                    targetDirectory = nil
                    newItemName = ""
                    showNewFolderDialog = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search Files", text: $searchText)
                    .font(.caption)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // File Tree
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredFiles) { node in
                        FileNodeRowView(
                            node: node,
                            depth: 0,
                            onTap: { handleTap(node: $0) },
                            onRename: { beginRename($0) },
                            onDelete: { deleteNode($0) },
                            onNewFile: { parent in
                                targetDirectory = parent.path
                                isCreatingFolder = false
                                newItemName = ""
                                showNewFileDialog = true
                            },
                            onNewFolder: { parent in
                                targetDirectory = parent.path
                                isCreatingFolder = true
                                newItemName = ""
                                showNewFolderDialog = true
                            },
                            settings: settings
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .alert(isCreatingFolder ? "New Folder" : "New File", isPresented: $showNewFileDialog) {
            TextField(isCreatingFolder ? "FolderName" : "FileName.swift", text: $newItemName)
                .autocorrectionDisabled()
            Button("Create") { createItem() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Folder", isPresented: $showNewFolderDialog) {
            TextField("Folder Name", text: $newItemName)
                .autocorrectionDisabled()
            Button("Create") { createItem() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: $showRenameDialog) {
            TextField("New Name", text: $renameText)
                .autocorrectionDisabled()
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { msg in Text(msg) }
    }

    private var expandAnimation: Animation {
        switch settings.fileNavigatorAnimationStyle {
        case .easeInOut: return .easeInOut(duration: settings.fileNavigatorAnimationSpeed)
        case .spring: return .spring(response: settings.fileNavigatorAnimationSpeed, dampingFraction: 0.75)
        case .bouncy: return .bouncy(duration: settings.fileNavigatorAnimationSpeed)
        }
    }

    // MARK: - Actions

    private func handleTap(node: FileNode) {
        guard !node.isDirectory else {
            withAnimation(expandAnimation) {
                node.isExpanded.toggle()
            }
            return
        }
        projectManager.openFile(node)
    }

    private func createItem() {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            if isCreatingFolder {
                try projectManager.createFolder(named: name, inDirectory: targetDirectory, project: project)
            } else {
                try projectManager.createFile(named: name, inDirectory: targetDirectory, project: project)
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        newItemName = ""
    }

    private func beginRename(_ node: FileNode) {
        nodeToRename = node
        renameText = node.name
        showRenameDialog = true
    }

    private func commitRename() {
        guard let node = nodeToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try projectManager.renameNode(node, to: name, project: project)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deleteNode(_ node: FileNode) {
        do {
            try projectManager.deleteNode(node, project: project)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Filter

    private func filterNodes(_ nodes: [FileNode], query: String) -> [FileNode] {
        nodes.compactMap { node -> FileNode? in
            if node.isDirectory {
                let filtered = filterNodes(node.children, query: query)
                if filtered.isEmpty && !node.name.lowercased().contains(query) { return nil }
                let copy = FileNode(name: node.name, path: node.path, isDirectory: true, children: filtered)
                copy.isExpanded = true
                return copy
            }
            return node.name.lowercased().contains(query) ? node : nil
        }
    }
}

// MARK: - File Node Row

struct FileNodeRowView: View {
    @ObservedObject var node: FileNode
    let depth: Int
    let onTap: (FileNode) -> Void
    let onRename: (FileNode) -> Void
    let onDelete: (FileNode) -> Void
    let onNewFile: (FileNode) -> Void
    let onNewFolder: (FileNode) -> Void
    let settings: AppSettings

    @EnvironmentObject private var projectManager: ProjectManager

    var isSelected: Bool {
        projectManager.activeFileNode?.id == node.id
    }

    private var iconTint: Color {
        if node.isDirectory { return Color(hex: settings.fileNavigatorFolderColorHex) }
        if node.name.hasSuffix(".swift") { return .orange }
        return Color(hex: settings.fileNavigatorDefaultFileColorHex)
    }

    private var iconName: String {
        if node.isDirectory { return settings.fileNavigatorFolderSymbol }
        if node.name.hasSuffix(".swift") { return "swift" }
        return settings.fileNavigatorFileSymbol
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Indent
                Spacer().frame(width: CGFloat(depth) * 16)

                // Expand chevron for directories
                if node.isDirectory {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                // Icon
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(iconTint)
                    .frame(width: 16)

                // Name
                Text(node.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                // Modified indicator
                if !node.isDirectory && projectManager.modifiedFilePaths.contains(node.path) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, settings.fileNavigatorLayoutStyle == .compact ? 5 : 9)
            .background(
                isSelected
                    ? Color.orange.opacity(0.25)
                    : Color.clear
            )
            .contentShape(Rectangle())
            .onTapGesture { onTap(node) }
            .contextMenu { nodeContextMenu }

            // Children
            if node.isDirectory && node.isExpanded {
                ForEach(node.children) { child in
                    FileNodeRowView(
                        node: child,
                        depth: depth + 1,
                        onTap: onTap,
                        onRename: onRename,
                        onDelete: onDelete,
                        onNewFile: onNewFile,
                        onNewFolder: onNewFolder,
                        settings: settings
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var nodeContextMenu: some View {
        if node.isDirectory {
            Button {
                onNewFile(node)
            } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }
            Button {
                onNewFolder(node)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Divider()
        }
        Button {
            onRename(node)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            onDelete(node)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
