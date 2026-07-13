import Foundation
import Observation

@Observable
@MainActor
public class GitViewModel {
    public var status: GitStatusSnapshot?
    public var history: [GitCommit] = []
    public var branches: [GitBranch] = []
    public var isScanning = false
    public var isGitInstalled = false
    public var repositoryURL: URL?

    public init() {}

    public func refreshInstallationStatus() async {
        isGitInstalled = await GitService.shared.isGitInstalled()
    }

    public func refreshStatus() async {
        guard let url = repositoryURL else { return }
        isScanning = true
        do {
            status = try await GitService.shared.getStatus(for: url)
            history = try await GitService.shared.getLog(repositoryURL: url)
            branches = try await GitService.shared.getBranches(repositoryURL: url)
        } catch {
            LoggingTool.error("Git status failed: \(error)")
        }
        isScanning = false
    }

    public func stage(_ file: GitFileStatus) async {
        guard let url = repositoryURL else { return }
        try? await GitService.shared.stage(path: file.path, repositoryURL: url)
        await refreshStatus()
    }

    public func unstage(_ file: GitFileStatus) async {
        guard let url = repositoryURL else { return }
        try? await GitService.shared.unstage(path: file.path, repositoryURL: url)
        await refreshStatus()
    }

    public func discardChanges(_ file: GitFileStatus) async {
        guard let url = repositoryURL else { return }
        try? await GitService.shared.discardChanges(path: file.path, repositoryURL: url)
        await refreshStatus()
    }

    public func commit(message: String) async {
        guard let url = repositoryURL else { return }
        try? await GitService.shared.commit(message: message, repositoryURL: url)
        await refreshStatus()
    }

    public func refreshBranches() {
        Task {
            await refreshStatus()
        }
    }

    public func createBranch(named name: String) {
        guard let url = repositoryURL else { return }
        Task {
            do {
                try await GitService.shared.createBranch(name: name, repositoryURL: url)
                await refreshStatus()
            } catch {
                LoggingTool.error("Git branch creation failed: \(error)")
            }
        }
    }

    public func checkout(_ branch: GitBranch) {
        guard let url = repositoryURL else { return }
        Task {
            do {
                try await GitService.shared.checkout(branch: branch.name, repositoryURL: url)
                await refreshStatus()
            } catch {
                LoggingTool.error("Git checkout failed: \(error)")
            }
        }
    }

    public func deleteBranch(_ branch: GitBranch) {
        guard let url = repositoryURL else { return }
        Task {
            do {
                try await GitService.shared.deleteBranch(name: branch.name, repositoryURL: url)
                await refreshStatus()
            } catch {
                LoggingTool.error("Git branch deletion failed: \(error)")
            }
        }
    }

    public func getDiff() async -> [GitDiffHunk] {
        guard let url = repositoryURL else { return [] }
        return (try? await GitService.shared.getDiff(repositoryURL: url)) ?? []
    }
}
