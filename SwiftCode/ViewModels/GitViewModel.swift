import Foundation
import Observation

@Observable
@MainActor
public class GitViewModel {
    public var status: GitStatusSnapshot?
    public var history: [GitCommit] = []
    public var branches: [GitBranch] = []
    public var isScanning = false
    public var repositoryURL: URL?

    public init() {}

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
}
