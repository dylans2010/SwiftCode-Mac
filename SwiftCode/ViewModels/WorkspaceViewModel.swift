import Foundation
import Observation

@Observable
@MainActor
public class WorkspaceViewModel: Sendable {
    public let projectURL: URL
    public let editor = EditorViewModel()
    public let projectTree = ProjectTreeViewModel()
    public let git = GitViewModel()
    public let build = BuildViewModel()
    public let debug = DebugSessionViewModel()
    public let ai = AgentViewModel()

    @ObservationIgnored nonisolated(unsafe) private var loadingTask: Task<Void, Never>?
    private var _cachedCapabilities: Set<LanguageCapability> = []

    public var projectCapabilities: Set<LanguageCapability> {
        _cachedCapabilities
    }

    private func updateCapabilities() {
        var caps: Set<LanguageCapability> = []

        func collectCapabilities(node: ProjectNode) {
            if node.kind == .file {
                if let provider = LanguageManager.shared.provider(for: node.url) {
                    caps.formUnion(provider.capabilities)
                }
            }
            node.children?.forEach(collectCapabilities)
        }

        if let root = projectTree.rootNode {
            collectCapabilities(node: root)
        }

        if caps.isEmpty {
            caps.insert(.format)
        }

        _cachedCapabilities = caps
    }

    public init(projectURL: URL) {
        self.projectURL = projectURL
        self.git.repositoryURL = projectURL
        self.loadingTask = Task {
            await git.refreshInstallationStatus()
            if Task.isCancelled { return }
            await projectTree.loadProject(url: projectURL)
            if Task.isCancelled { return }
            updateCapabilities()
            await git.refreshStatus()
        }
    }

    deinit {
        let task = loadingTask
        Task.detached {
            task?.cancel()
        }
    }

    public func handleFileSelectionChange(nodeID: String?) {
        guard let nodeID = nodeID else { return }
        // We need to find the node in the tree to get its URL.
        // For now, we can assume the ID is the path.
        let url = URL(fileURLWithPath: nodeID)
        Task {
            await editor.openFile(url: url)
        }
    }
}
