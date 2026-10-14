import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - SDKCodeFileNavigatorView
//
// The Studio code editor's file navigator sidebar. Renders an
// `SDKCodeFileNode` tree as a native macOS `List` with lazy directory
// enumeration: directories load their children off the main thread the
// first time they expand (spinner while loading, per the node's
// `needsLoading` contract), and collapsing preserves loaded children so
// re-expanding is free.

@MainActor
public struct SDKCodeFileNavigatorView: View {
    @ObservedObject public var editorState: SDKCodeEditorState

    @StateObject private var model = SDKFileTreeModel()
    @State private var pendingEntryKind: SDKCodeEntryKind?
    @State private var newEntryName = ""
    @State private var alert: SDKFileNavigatorAlert?

    public init(editorState: SDKCodeEditorState) {
        self.editorState = editorState
    }

    public var body: some View {
        VStack(spacing: 0) {
            SDKCodeProjectRootView(rootURL: model.root?.url ?? editorState.projectRootURL) { url in
                editorState.setProjectRoot(url)
                model.setRoot(url)
            }
            Divider()
            if model.root == nil {
                noProjectView
            } else {
                List(model.visibleRows(), selection: $model.selectionID) { row in
                    fileRow(row)
                        .tag(row.node.id)
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear {
            if let rootURL = editorState.projectRootURL, model.root?.url != rootURL {
                model.setRoot(rootURL)
            }
        }
        .onChange(of: editorState.projectRootURL) { _, newURL in
            if let newURL, model.root?.url != newURL {
                model.setRoot(newURL)
            }
        }
        .toolbar { navigatorToolbar }
        .sheet(item: $pendingEntryKind) { kind in
            newEntrySheet(kind)
        }
        .alert(item: $alert) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func fileRow(_ row: SDKFileTreeRow) -> some View {
        let node = row.node
        HStack(spacing: 5) {
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            } else {
                Color.clear.frame(width: 14, height: 14)
            }
            if model.loadingIDs.contains(node.id) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: systemImage(for: node))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(node.isDirectory ? .secondary : .primary)
            }
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory {
                model.toggle(node)
            } else {
                openFile(node)
            }
        }
    }

    private var noProjectView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No Project Open")
                .font(.headline)
            Text("Open a project folder to browse its files.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var navigatorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                pendingEntryKind = .file
            } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }
            .disabled(model.root == nil)
            .help("Create a new empty file in the selected folder")
            Button {
                pendingEntryKind = .folder
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .disabled(model.root == nil)
            .help("Create a new folder in the selected folder")
            Button(action: revealSelectedInFinder) {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .disabled(model.selectionID == nil)
            .help("Reveal the selected item in Finder")
            Button(action: { model.refreshAll() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.root == nil)
            .help("Re-read the project folder from disk")
        }
    }

    // MARK: - Actions

    private func openFile(_ node: SDKCodeFileNode) {
        guard !node.isDirectory else { return }
        model.selectionID = node.id
        do {
            try editorState.openFile(node.url)
        } catch SDKCodeEditorError.unreadableFile(_, let reason) {
            alert = SDKFileNavigatorAlert(
                title: "Could Not Open “\(node.name)”",
                message: reason
            )
            editorState.appendConsole(.system("Could not open \(node.name): \(reason)"))
        } catch {
            alert = SDKFileNavigatorAlert(
                title: "Could Not Open “\(node.name)”",
                message: error.localizedDescription
            )
            editorState.appendConsole(.system("Could not open \(node.name): \(error.localizedDescription)"))
        }
    }

    private func revealSelectedInFinder() {
        guard let selectionID = model.selectionID else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selectionID)])
    }

    private func createEntry(kind: SDKCodeEntryKind) {
        let name = newEntryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), let dir = model.selectedDirectoryURL() else { return }
        let url = dir.appendingPathComponent(name)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            alert = SDKFileNavigatorAlert(
                title: "Name Already Exists",
                message: "“\(name)” already exists in “\(dir.lastPathComponent)”."
            )
            return
        }
        do {
            if kind == .file {
                let created = fileManager.createFile(atPath: url.path, contents: Data(), attributes: nil)
                if !created {
                    throw SDKFileNavigatorError.creationFailed(url: url)
                }
            } else {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            }
        } catch {
            alert = SDKFileNavigatorAlert(
                title: kind == .file ? "Could Not Create File" : "Could Not Create Folder",
                message: error.localizedDescription
            )
            return
        }
        model.expand(id: dir.path)
        model.refresh(id: dir.path)
        model.selectionID = url.path
        pendingEntryKind = nil
        if kind == .file {
            openFile(SDKCodeFileNode(url: url, isDirectory: false))
        }
    }

    @ViewBuilder
    private func newEntrySheet(_ kind: SDKCodeEntryKind) -> some View {
        let targetDir = model.selectedDirectoryURL()
        VStack(alignment: .leading, spacing: 12) {
            Text(kind == .file ? "New File" : "New Folder")
                .font(.headline)
            if let targetDir {
                Text("In \(targetDir.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField(
                kind == .file ? "Filename (e.g. main.swift)" : "Folder name",
                text: $newEntryName
            )
            .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { pendingEntryKind = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { createEntry(kind: kind) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        newEntryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || targetDir == nil
                    )
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { newEntryName = "" }
    }

    private func systemImage(for node: SDKCodeFileNode) -> String {
        if node.isDirectory {
            return node.isExpanded ? "folder.fill" : "folder"
        }
        switch SDKCodeLanguage.infer(fromFileURL: node.url) {
        case .swift:
            return "swift"
        case .typescript, .javascript:
            return "curlybraces"
        case .json:
            return "braces"
        case .markdown:
            return "doc.richtext"
        case .plaintext:
            return node.url.pathExtension.isEmpty ? "doc" : "doc.plaintext"
        }
    }
}

// MARK: - Supporting types

private struct SDKFileTreeRow: Identifiable {
    let node: SDKCodeFileNode
    let depth: Int
    var id: String { node.id }
}

private enum SDKCodeEntryKind: String, Identifiable {
    case file
    case folder
    var id: String { rawValue }
}

private struct SDKFileNavigatorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum SDKFileNavigatorError: LocalizedError {
    case creationFailed(url: URL)
    var errorDescription: String? {
        switch self {
        case .creationFailed(let url):
            return "FileManager could not create a file at \(url.path)."
        }
    }
}

// MARK: - SDKFileTreeModel

@MainActor
private final class SDKFileTreeModel: ObservableObject {
    @Published var root: SDKCodeFileNode?
    @Published var loadingIDs: Set<String> = []
    @Published var selectionID: String?

    func setRoot(_ url: URL) {
        loadingIDs.removeAll()
        root = SDKCodeFileNode(url: url, isDirectory: true, isExpanded: true)
        selectionID = url.path
        loadChildrenIfNeeded(forID: url.path)
    }

    func toggle(_ node: SDKCodeFileNode) {
        guard node.isDirectory,
              let root,
              let current = find(id: node.id, in: root)
        else { return }
        let expanded = !current.isExpanded
        updateNode(id: current.id) {
            SDKCodeFileNode(url: $0.url, isDirectory: true, children: $0.children, isExpanded: expanded)
        }
        if expanded {
            loadChildrenIfNeeded(forID: current.id)
        }
    }

    func expand(id: String) {
        updateNode(id: id) {
            SDKCodeFileNode(url: $0.url, isDirectory: true, children: $0.children, isExpanded: true)
        }
        loadChildrenIfNeeded(forID: id)
    }

    func refresh(id: String) {
        updateNode(id: id) {
            SDKCodeFileNode(url: $0.url, isDirectory: true, children: nil, isExpanded: $0.isExpanded)
        }
        loadingIDs.remove(id)
        if let root, let node = find(id: id, in: root), node.isExpanded {
            loadChildren(of: node)
        }
    }

    func refreshAll() {
        guard let root else { return }
        for id in expandedDirectoryIDs(in: root) {
            refresh(id: id)
        }
    }

    func selectedDirectoryURL() -> URL? {
        if let selectionID, let root, let node = find(id: selectionID, in: root) {
            return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        }
        return root?.url
    }

    func visibleRows() -> [SDKFileTreeRow] {
        guard let root, let children = root.children else { return [] }
        var rows: [SDKFileTreeRow] = []
        for child in children {
            append(node: child, depth: 0, to: &rows)
        }
        return rows
    }

    // MARK: - Loading

    private func loadChildrenIfNeeded(forID id: String) {
        guard let root, let node = find(id: id, in: root), node.needsLoading else { return }
        loadChildren(of: node)
    }

    private func loadChildren(of node: SDKCodeFileNode) {
        let id = node.id
        guard !loadingIDs.contains(id) else { return }
        loadingIDs.insert(id)
        let url = node.url
        Task.detached(priority: .userInitiated) {
            let children = SDKFileTreeModel.enumerateChildren(of: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updateNode(id: id) { $0.withChildren(children) }
                self.loadingIDs.remove(id)
            }
        }
    }

    private nonisolated static func enumerateChildren(of url: URL) -> [SDKCodeFileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let listing: [URL]
        do {
            listing = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: []
            )
        } catch {
            return []
        }
        var directories: [SDKCodeFileNode] = []
        var files: [SDKCodeFileNode] = []
        for childURL in listing {
            let isDirectory = (try? childURL.resourceValues(forKeys: Set(keys)).isDirectory) ?? false
            let node = SDKCodeFileNode(url: childURL, isDirectory: isDirectory)
            if isDirectory {
                directories.append(node)
            } else {
                files.append(node)
            }
        }
        let byName = { (lhs: SDKCodeFileNode, rhs: SDKCodeFileNode) in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        directories.sort(by: byName)
        files.sort(by: byName)
        return directories + files
    }

    // MARK: - Tree surgery

    private func updateNode(id: String, transform: (SDKCodeFileNode) -> SDKCodeFileNode) {
        guard let root else { return }
        self.root = mapTree(root, id: id, transform: transform)
    }

    private func mapTree(
        _ node: SDKCodeFileNode,
        id: String,
        transform: (SDKCodeFileNode) -> SDKCodeFileNode
    ) -> SDKCodeFileNode {
        if node.id == id { return transform(node) }
        guard node.isDirectory, let children = node.children else { return node }
        return SDKCodeFileNode(
            url: node.url,
            isDirectory: true,
            children: children.map { mapTree($0, id: id, transform: transform) },
            isExpanded: node.isExpanded
        )
    }

    private func find(id: String, in node: SDKCodeFileNode) -> SDKCodeFileNode? {
        if node.id == id { return node }
        guard let children = node.children else { return nil }
        for child in children {
            if let found = find(id: id, in: child) { return found }
        }
        return nil
    }

    private func expandedDirectoryIDs(in node: SDKCodeFileNode) -> [String] {
        var ids: [String] = []
        collectExpanded(node, into: &ids)
        return ids
    }

    private func collectExpanded(_ node: SDKCodeFileNode, into ids: inout [String]) {
        guard node.isDirectory, node.isExpanded else { return }
        ids.append(node.id)
        for child in node.children ?? [] {
            collectExpanded(child, into: &ids)
        }
    }

    private func append(node: SDKCodeFileNode, depth: Int, to rows: inout [SDKFileTreeRow]) {
        rows.append(SDKFileTreeRow(node: node, depth: depth))
        guard node.isDirectory, node.isExpanded, let children = node.children else { return }
        for child in children {
            append(node: child, depth: depth + 1, to: &rows)
        }
    }
}
