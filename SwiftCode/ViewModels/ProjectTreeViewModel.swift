import Foundation
import Observation

@Observable
@MainActor
public class ProjectTreeViewModel {
    public var rootNode: ProjectNode?
    public var isLoading = false

    public init() {}

    public func loadProject(url: URL) async {
        isLoading = true
        do {
            let children = try await FileSystemService.shared.listDirectory(at: url)
            rootNode = ProjectNode(url: url, kind: .folder, children: children)
        } catch {
            LoggingTool.error("Failed to load project tree: \(error)")
        }
        isLoading = false
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
                    newNode.children = try await FileSystemService.shared.listDirectory(at: node.url)
                } catch {
                    LoggingTool.error("Failed to expand node: \(error)")
                }
            } else {
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
