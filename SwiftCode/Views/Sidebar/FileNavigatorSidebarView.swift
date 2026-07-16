import SwiftUI
import AppKit

// MARK: - FileSymbolsShow (Central symbol registry with AppSettings integration)

@MainActor
public struct FileSymbolsShow {
    public static func symbol(forPathExtension ext: String, isFolder: Bool = false) -> String {
        if isFolder {
            return AppSettings.shared.fileNavigatorFolderSymbol.isEmpty ? "folder.fill" : AppSettings.shared.fileNavigatorFolderSymbol
        }

        let cleaned = ext.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == "swift" {
            return AppSettings.shared.fileNavigatorFileSymbol.isEmpty ? "swift" : AppSettings.shared.fileNavigatorFileSymbol
        }

        switch cleaned {
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

    public static func color(forPathExtension ext: String, isFolder: Bool = false) -> Color {
        if isFolder {
            return Color(hex: AppSettings.shared.fileNavigatorFolderColorHex)
        }
        let cleaned = ext.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == "swift" {
            return Color(hex: AppSettings.shared.fileNavigatorSwiftFileColorHex)
        }
        return Color(hex: AppSettings.shared.fileNavigatorDefaultFileColorHex)
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

@MainActor
struct FileNavigatorSidebarView: View {
    @Bindable var viewModel: ProjectTreeViewModel
    @Environment(WorkspaceViewModel.self) var workspaceViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var favorites: [String] = []
    @State private var recents: [String] = []

    // Inline Rename State
    @State private var renamingNodeID: String? = nil
    @State private var inlineRenameText = ""

    // Legacy sheet structures maintained for robust backup
    @State private var showingRenameSheet = false
    @State private var selectedNodeForRename: ProjectNode?
    @State private var renameText = ""

    @State private var showingDeleteConfirm = false
    @State private var selectedNodeForDelete: ProjectNode?

    @State private var selectedNodeForWorkflow: ProjectNode?
    @State private var showingWorkflowPopover = false

    private static let favoritesKey = "com.swiftcode.sidebar.favorites"
    private static let recentsKey = "com.swiftcode.sidebar.recents"

    private var activeAnimation: Animation {
        let speed = settings.fileNavigatorAnimationSpeed
        switch settings.fileNavigatorAnimationStyle {
        case .spring:
            return .spring(response: speed, dampingFraction: 0.8)
        case .bouncy:
            return .bouncy(duration: speed)
        case .easeInOut:
            return .easeInOut(duration: speed)
        }
    }

    private var verticalPadding: CGFloat {
        settings.fileNavigatorLayoutStyle == .expanded ? 8 : 4
    }

    var body: some View {
        VStack(spacing: 0) {
            // macOS Native Search Header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Filter files...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // Dynamic Action Bar Header
            HStack(spacing: 12) {
                Button(action: {
                    createNewFileInActiveDir()
                }) {
                    Image(systemName: "plus")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.plain)
                .help("New File")
                .disabled(viewModel.projectURL == nil)

                Button(action: {
                    createNewFolderInActiveDir()
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
                        loadFavoritesAndRecents()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .overlay(
                Divider(), alignment: .bottom
            )

            // Modern Navigation Sidebar List
            List(selection: $viewModel.selectedNodeID) {
                if let error = viewModel.loadError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding()
                }

                // 1. Favorites Section (if non-empty)
                if !favorites.isEmpty && searchText.isEmpty {
                    Section(header: Text("FAVORITES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)) {
                            ForEach(favorites, id: \.self) { path in
                                let url = URL(fileURLWithPath: path)
                                let fakeNode = ProjectNode(url: url, kind: .file)
                                fileRow(for: fakeNode, indent: 0)
                            }
                        }
                }

                // 2. Recents Section (if non-empty)
                if !recents.isEmpty && searchText.isEmpty {
                    Section(header: Text("RECENTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)) {
                            ForEach(recents, id: \.self) { path in
                                let url = URL(fileURLWithPath: path)
                                let fakeNode = ProjectNode(url: url, kind: .file)
                                fileRow(for: fakeNode, indent: 0)
                            }
                        }
                }

                // 3. Project Tree Section
                if let rootNode = viewModel.rootNode {
                    Section(header: Text("PROJECT FILES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)) {
                            if !searchText.isEmpty {
                                // Search active: display flattened filtered matches
                                ForEach(flattenedAndFilteredNodes(root: rootNode)) { node in
                                    fileRow(for: node, indent: 0)
                                }
                            } else {
                                // Normal tree disclosure view hierarchy
                                ProjectTreeNodeView(
                                    node: rootNode,
                                    viewModel: viewModel,
                                    gitViewModel: workspaceViewModel.git,
                                    favorites: $favorites,
                                    recents: $recents,
                                    renamingNodeID: $renamingNodeID,
                                    inlineRenameText: $inlineRenameText,
                                    onRename: { node in
                                        renamingNodeID = node.id
                                        inlineRenameText = node.url.lastPathComponent
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
                            }
                        }
                } else if !viewModel.isLoading {
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
            .animation(activeAnimation, value: viewModel.expandedNodeIDs)
        }
        .onAppear {
            loadFavoritesAndRecents()
        }
        .onChange(of: viewModel.selectedNodeID) { oldValue, newValue in
            if let id = newValue {
                workspaceViewModel.handleFileSelectionChange(nodeID: id)
                appendToRecents(path: id)
            }
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
                        viewModel.invalidateCache(at: node.url.deletingLastPathComponent())
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
                        renamingNodeID = node.id
                        inlineRenameText = node.url.lastPathComponent
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

    // MARK: - Helper Views & Operations

    @ViewBuilder
    private func fileRow(for node: ProjectNode, indent: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: FileSymbolsShow.symbol(forPathExtension: node.url.pathExtension, isFolder: node.kind == .folder))
                .foregroundStyle(FileSymbolsShow.color(forPathExtension: node.url.pathExtension, isFolder: node.kind == .folder))
                .font(.subheadline)
                .frame(width: 16)

            if renamingNodeID == node.id {
                TextField("Rename...", text: $inlineRenameText, onCommit: {
                    commitInlineRename(for: node)
                })
                .textFieldStyle(.plain)
                .font(.subheadline)
                .onSubmit {
                    commitInlineRename(for: node)
                }
            } else {
                Text(node.url.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Spacer()

            // Git Decoration Badges
            if let decoration = gitDecoration(for: node) {
                Text(decoration.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(decoration.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(decoration.color.opacity(0.12))
                    .cornerRadius(4)
            }

            // Favorite Star indicator
            if favorites.contains(node.url.path) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.leading, indent)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
        .onFileDoubleClick {
            selectedNodeForWorkflow = node
            showingWorkflowPopover = true
        }
        .onDrag {
            NSItemProvider(object: node.url.path as NSString)
        }
        .contextMenu {
            Button("Open in Editor") {
                viewModel.selectedNodeID = node.id
            }

            Button(favorites.contains(node.url.path) ? "Remove from Favorites" : "Add to Favorites") {
                toggleFavorite(path: node.url.path)
            }

            Button("Rename Inline...") {
                renamingNodeID = node.id
                inlineRenameText = node.url.lastPathComponent
            }

            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(node.url.path, inFileViewerRootedAtPath: "")
            }

            Divider()

            Button("Delete", role: .destructive) {
                selectedNodeForDelete = node
                showingDeleteConfirm = true
            }
        }
        .tag(node.url.path)
    }

    private func gitDecoration(for node: ProjectNode) -> (label: String, color: Color)? {
        guard let gitStatus = workspaceViewModel.git.status else { return nil }
        // Find matching status record for this node's path
        if let match = gitStatus.files.first(where: { $0.path.path == node.url.path }) {
            switch match.status {
            case .modified:
                return ("M", .blue)
            case .added:
                return ("A", .green)
            case .untracked:
                return ("?", .green)
            case .deleted:
                return ("D", .red)
            case .renamed:
                return ("R", .purple)
            case .conflicted:
                return ("U", .orange)
            }
        }
        return nil
    }

    private func commitInlineRename(for node: ProjectNode) {
        let trimmed = inlineRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != node.url.lastPathComponent else {
            renamingNodeID = nil
            return
        }

        Task {
            let newURL = node.url.deletingLastPathComponent().appendingPathComponent(trimmed)
            do {
                try FileManager.default.moveItem(at: node.url, to: newURL)
                viewModel.invalidateCache(at: node.url.deletingLastPathComponent())
                await viewModel.refresh()
                renamingNodeID = nil
            } catch {
                LoggingTool.error("Rename failed: \(error.localizedDescription)")
                renamingNodeID = nil
            }
        }
    }

    private func createNewFileInActiveDir() {
        Task {
            guard let projectURL = viewModel.projectURL else { return }
            let name = "Untitled.swift"
            let newFileURL = projectURL.appendingPathComponent(name)
            try? await FileSystemService.shared.createFile(at: newFileURL)
            viewModel.invalidateCache(at: projectURL)
            await viewModel.refresh()
        }
    }

    private func createNewFolderInActiveDir() {
        Task {
            guard let projectURL = viewModel.projectURL else { return }
            let newFolderURL = projectURL.appendingPathComponent("New Folder")
            try? await FileSystemService.shared.createDirectory(at: newFolderURL)
            viewModel.invalidateCache(at: projectURL)
            await viewModel.refresh()
        }
    }

    private func toggleFavorite(path: String) {
        if favorites.contains(path) {
            favorites.removeAll { $0 == path }
        } else {
            favorites.append(path)
        }
        UserDefaults.standard.set(favorites, forKey: Self.favoritesKey)
    }

    private func appendToRecents(path: String) {
        recents.removeAll { $0 == path }
        recents.insert(path, at: 0)
        recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
    }

    private func loadFavoritesAndRecents() {
        favorites = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        recents = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    private func flattenedAndFilteredNodes(root: ProjectNode) -> [ProjectNode] {
        var results: [ProjectNode] = []
        func traverse(node: ProjectNode) {
            if node.url.lastPathComponent.localizedCaseInsensitiveContains(searchText) && node.id != root.id {
                results.append(node)
            }
            if let children = node.children {
                for child in children {
                    traverse(node: child)
                }
            }
        }
        traverse(node: root)
        return results
    }
}

// MARK: - ProjectTreeNodeView

struct ProjectTreeNodeView: View {
    let node: ProjectNode
    @Bindable var viewModel: ProjectTreeViewModel
    let gitViewModel: GitViewModel
    @Binding var favorites: [String]
    @Binding var recents: [String]
    @Binding var renamingNodeID: String?
    @Binding var inlineRenameText: String
    let onRename: (ProjectNode) -> Void
    let onDelete: (ProjectNode) -> Void
    let onDoubleClick: (ProjectNode) -> Void

    @EnvironmentObject private var settings: AppSettings

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { viewModel.expandedNodeIDs.contains(node.url.path) },
            set: { newValue in
                Task {
                    if newValue != viewModel.expandedNodeIDs.contains(node.url.path) {
                        await viewModel.toggleExpanded(node)
                    }
                }
            }
        )
    }

    private var verticalPadding: CGFloat {
        settings.fileNavigatorLayoutStyle == .expanded ? 8 : 4
    }

    var body: some View {
        if node.kind == .folder {
            DisclosureGroup(isExpanded: isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        ProjectTreeNodeView(
                            node: child,
                            viewModel: viewModel,
                            gitViewModel: gitViewModel,
                            favorites: $favorites,
                            recents: $recents,
                            renamingNodeID: $renamingNodeID,
                            inlineRenameText: $inlineRenameText,
                            onRename: onRename,
                            onDelete: onDelete,
                            onDoubleClick: onDoubleClick
                        )
                    }
                } else if viewModel.expandedNodeIDs.contains(node.url.path) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding(.leading, 8)
                }
            } label: {
                nodeRowContent
            }
        } else {
            nodeRowContent
        }
    }

    private var nodeRowContent: some View {
        HStack(spacing: 8) {
            if viewModel.loadingNodeIDs.contains(node.url.path) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 16)
            } else {
                Image(systemName: FileSymbolsShow.symbol(forPathExtension: node.url.pathExtension, isFolder: node.kind == .folder))
                    .foregroundStyle(FileSymbolsShow.color(forPathExtension: node.url.pathExtension, isFolder: node.kind == .folder))
                    .font(.subheadline)
                    .frame(width: 16)
            }

            if renamingNodeID == node.id {
                TextField("Rename...", text: $inlineRenameText, onCommit: {
                    commitInlineRename()
                })
                .textFieldStyle(.plain)
                .font(.subheadline)
                .onSubmit {
                    commitInlineRename()
                }
            } else {
                Text(node.url.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Spacer()

            // Git Badges
            if let decoration = gitDecoration() {
                Text(decoration.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(decoration.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(decoration.color.opacity(0.12))
                    .cornerRadius(4)
            }

            // Favorite Indicator
            if favorites.contains(node.url.path) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onFileDoubleClick {
            onDoubleClick(node)
        }
        .onDrag {
            NSItemProvider(object: node.url.path as NSString)
        }
        .contextMenu {
            Button("Open in Editor") {
                viewModel.selectedNodeID = node.id
            }

            Button(favorites.contains(node.url.path) ? "Remove from Favorites" : "Add to Favorites") {
                toggleFavorite(path: node.url.path)
            }

            Button("Rename Inline...") {
                renamingNodeID = node.id
                inlineRenameText = node.url.lastPathComponent
            }

            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(node.url.path, inFileViewerRootedAtPath: "")
            }

            Divider()

            Button("Delete", role: .destructive) {
                onDelete(node)
            }
        }
        .tag(node.url.path)
    }

    private func gitDecoration() -> (label: String, color: Color)? {
        guard let gitStatus = gitViewModel.status else { return nil }
        if let match = gitStatus.files.first(where: { $0.path.path == node.url.path }) {
            switch match.status {
            case .modified:
                return ("M", .blue)
            case .added:
                return ("A", .green)
            case .untracked:
                return ("?", .green)
            case .deleted:
                return ("D", .red)
            case .renamed:
                return ("R", .purple)
            case .conflicted:
                return ("U", .orange)
            }
        }
        return nil
    }

    private func toggleFavorite(path: String) {
        if favorites.contains(path) {
            favorites.removeAll { $0 == path }
        } else {
            favorites.append(path)
        }
        UserDefaults.standard.set(favorites, forKey: "com.swiftcode.sidebar.favorites")
    }

    private func commitInlineRename() {
        let trimmed = inlineRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != node.url.lastPathComponent else {
            renamingNodeID = nil
            return
        }

        Task {
            let newURL = node.url.deletingLastPathComponent().appendingPathComponent(trimmed)
            do {
                try FileManager.default.moveItem(at: node.url, to: newURL)
                viewModel.invalidateCache(at: node.url.deletingLastPathComponent())
                await viewModel.refresh()
                renamingNodeID = nil
            } catch {
                LoggingTool.error("Rename failed: \(error.localizedDescription)")
                renamingNodeID = nil
            }
        }
    }
}
