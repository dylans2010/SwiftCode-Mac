import Foundation

public struct SourceControlSnapshot: Sendable {
    public var repository: GitRepository?
    public var status: [String: GitRepository.FileStatus] = [:]
    public var changes: [GitRepository.Change] = []
    public var currentBranch: String?
    public var head: String?
    public var branches: [GitRepository.Ref] = []
    public var recentBranches: [String] = []
    public var tags: [GitRepository.Ref] = []
    public var stashes: [String] = []
    public var remotes: [GitRepository.Remote] = []
    public var remoteBranches: [GitRepository.Ref] = []
    public var integration: GitRepository.IntegrationState = .none
    public var debugBarBranch: String?

    public init(repository: GitRepository? = nil) { self.repository = repository }

    package func baselinesMayDiffer(from other: SourceControlSnapshot) -> Bool {
        repository?.root != other.repository?.root || head != other.head || currentBranch != other.currentBranch || changes != other.changes
            || integration != other.integration
    }

    public static func read(workspace: URL, known: GitRepository??, branchFolder: String?) -> SourceControlSnapshot {
        let repo: GitRepository? = known ?? GitRepository(containing: workspace)
        var s = SourceControlSnapshot(repository: repo)
        s.debugBarBranch = branchFolder.flatMap(GitBranchLookup.current(at:))
        guard let repo else { return s }
        s.status = (try? repo.status()) ?? [:]
        s.remotes = (try? repo.remotes()) ?? []
        s.branches = (try? repo.branches()) ?? []
        s.tags = (try? repo.tags()) ?? []
        s.remoteBranches = (try? repo.remoteBranches()) ?? []
        s.currentBranch = repo.currentBranch()
        s.head = repo.headHash()
        s.changes = (try? repo.changes()) ?? []
        s.recentBranches = repo.recentBranches()
        s.stashes = repo.stashes()
        s.integration = repo.integrationState()
        return s
    }
}
