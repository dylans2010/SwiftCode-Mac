import Foundation
import Observation

@Observable
@MainActor
public class ProjectTreeViewModel {
    public var rootNode: ProjectNode?
    public var isLoading = false
    public var selectedNodeID: String?

    public var projectURL: URL? {
        rootNode?.url
    }

    public init() {}

    public var loadError: String?

    public func loadProject(url: URL) async {
        isLoading = true
        loadError = nil
        do {
            // Root-only loading for initial tree state
            let children = try await FileSystemService.shared.listDirectory(at: url, recursive: false)
            rootNode = ProjectNode(url: url, kind: .folder, children: children)
        } catch {
            loadError = "Failed to load project: \(error.localizedDescription)"
            LoggingTool.error("Failed to load project tree: \(error)")
        }
        isLoading = false
    }

    public func refresh() async {
        guard let projectURL else { return }
        await loadProject(url: projectURL)
    }

    public func toggleExpanded(_ node: ProjectNode) async {
        guard node.kind == .folder else { return }

        // Find the node in the tree and update its children
        if let root = rootNode {
            rootNode = await updateNode(root, targetID: node.id)
        }
    }

    private func updateNode(_ node: ProjectNode, targetID: String) async -> ProjectNode {
        var newNode = node
        if node.id == targetID {
            if node.children == nil {
                do {
                    // Lazy load children
                    newNode.children = try await FileSystemService.shared.listDirectory(at: node.url, recursive: false)
                } catch {
                    LoggingTool.error("Failed to expand node: \(error)")
                }
            } else {
                // Collapse folder by clearing children
                newNode.children = nil
            }
            return newNode
        }

        if let children = node.children {
            var updatedChildren: [ProjectNode] = []
            for child in children {
                updatedChildren.append(await updateNode(child, targetID: targetID))
            }
            newNode.children = updatedChildren
        }
        return newNode
    }
}
