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
    private let sessionStore = ProjectSessionStore.shared

    @ObservationIgnored nonisolated(unsafe) private var loadingTask: Task<Void, Never>?

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
        // The ID is the full path of the file
        let url = URL(fileURLWithPath: nodeID)

        // Ensure it's not a directory (IDs for folders also come through here)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: nodeID, isDirectory: &isDir), isDir.boolValue {
            return
        }

        Task {
            if let project = sessionStore.activeProject,
               let node = project.files.first(where: { url.path.hasSuffix($0.path) }) {
                sessionStore.openFile(node)
            }
            await editor.openFile(url: url)
        }
    }
}
