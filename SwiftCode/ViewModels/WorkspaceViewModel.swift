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

    public init(projectURL: URL) {
        self.projectURL = projectURL
        self.git.repositoryURL = projectURL
        Task {
            await projectTree.loadProject(url: projectURL)
            await git.refreshStatus()
        }
    }
}
