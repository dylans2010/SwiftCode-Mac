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

    private var loadingTask: Task<Void, Never>?

    public init(projectURL: URL) {
        self.projectURL = projectURL
        self.git.repositoryURL = projectURL
        self.loadingTask = Task {
            await git.refreshInstallationStatus()
            if Task.isCancelled { return }
            await projectTree.loadProject(url: projectURL)
            if Task.isCancelled { return }
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
