// Ported from Legacy `SwiftCode/SDK/Studio/CodeEditor/Views/SDKCodeFileNavigatorView.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: SDKFileTreeRow, SDKCodeEntryKind, SDKFileNavigatorAlert, SDKFileNavigatorError, SDKFileTreeModel.
// Combine/@Published converted to @Observable.

import AppKit
import Foundation
import SwiftUI

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

@MainActor
@Observable
private final class SDKFileTreeModel {
    var root: SDKCodeFileNode?
    var loadingIDs: Set<String> = []
    var selectionID: String?

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
