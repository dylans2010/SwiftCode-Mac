import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.ViewModels", category: "ProjectTreeViewModel")

@Observable
@MainActor
public class ProjectTreeViewModel {
    public var rootNode: ProjectNode?
    public var isLoading = false
    public var selectedNodeID: String?

    // Performance optimizations: Caching, load tracking, expansion tracking
    public var expandedNodeIDs: Set<String> = []
    public var cachedChildren: [String: [ProjectNode]] = [:]
    public var loadingNodeIDs: Set<String> = []

    @ObservationIgnored
    private var activeLoads: [String: Task<[ProjectNode], Error>] = [:]

    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    public var projectURL: URL? {
        rootNode?.url
    }

    public init() {}

    public var loadError: String?

    public func loadProject(url: URL) async {
        isLoading = true
        loadError = nil
        expandedNodeIDs.removeAll()
        cachedChildren.removeAll()

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let children = try await fetchChildren(at: url)
            rootNode = ProjectNode(url: url, kind: .folder, children: children)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("Loaded project root in \(duration, format: .fixed(precision: 4)) seconds.")
        } catch {
            loadError = "Failed to load project: \(error.localizedDescription)"
            logger.error("Failed to load project tree: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    public func refresh() async {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            if Task.isCancelled { return }

            guard let projectURL else { return }

            isLoading = true
            loadError = nil

            // Clear cache for fresh read on manual refresh
            cachedChildren.removeAll()

            let startTime = CFAbsoluteTimeGetCurrent()
            do {
                let children = try await fetchChildren(at: projectURL)
                var root = ProjectNode(url: projectURL, kind: .folder, children: children)
                root = await rebuildNodeRecursively(root)
                self.rootNode = root
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                logger.info("Refreshed project tree in \(duration, format: .fixed(precision: 4)) seconds.")
            } catch {
                loadError = "Failed to refresh project: \(error.localizedDescription)"
                logger.error("Failed to refresh project tree: \(error.localizedDescription, privacy: .public)")
            }
            isLoading = false
        }
        _ = await refreshTask?.result
    }

    public func toggleExpanded(_ node: ProjectNode) async {
        guard node.kind == .folder else { return }

        let path = node.url.path
        if expandedNodeIDs.contains(path) {
            // Collapse: remove from expanded list and cancel loads
            expandedNodeIDs.remove(path)
            if let loadTask = activeLoads[path] {
                loadTask.cancel()
                activeLoads.removeValue(forKey: path)
            }
        } else {
            // Expand: add to expanded list
            expandedNodeIDs.insert(path)
        }

        if let root = rootNode {
            loadingNodeIDs.insert(path)
            rootNode = await rebuildNodeRecursively(root)
            loadingNodeIDs.remove(path)
        }
    }

    // MARK: - Internal Tree Helpers

    private func fetchChildren(at url: URL) async throws -> [ProjectNode] {
        let path = url.path

        if let cached = cachedChildren[path] {
            return cached
        }

        if let inFlight = activeLoads[path] {
            return try await inFlight.value
        }

        let task = Task<[ProjectNode], Error> {
            try await FileSystemService.shared.listDirectory(at: url, recursive: false)
        }

        activeLoads[path] = task

        do {
            let children = try await task.value
            activeLoads[path] = nil
            cachedChildren[path] = children
            return children
        } catch {
            activeLoads[path] = nil
            throw error
        }
    }

    private func rebuildNodeRecursively(_ node: ProjectNode) async -> ProjectNode {
        var newNode = node
        let path = node.url.path

        if expandedNodeIDs.contains(path) {
            do {
                let children = try await fetchChildren(at: node.url)
                var rebuilt: [ProjectNode] = []
                for child in children {
                    if child.kind == .folder {
                        rebuilt.append(await rebuildNodeRecursively(child))
                    } else {
                        rebuilt.append(child)
                    }
                }
                newNode.children = rebuilt
            } catch {
                logger.error("Failed to load children for expanded folder \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        } else {
            newNode.children = nil
        }
        return newNode
    }

    public func invalidateCache(at url: URL) {
        let path = url.path
        cachedChildren.removeValue(forKey: path)

        var current = url.deletingLastPathComponent()
        while current.path != "/" && current.path != projectURL?.deletingLastPathComponent().path {
            cachedChildren.removeValue(forKey: current.path)
            current = current.deletingLastPathComponent()
        }
    }
}
