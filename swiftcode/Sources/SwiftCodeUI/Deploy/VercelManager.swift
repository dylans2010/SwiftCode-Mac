import Foundation
import SwiftCodeGitHub
import SwiftCodeIDECore

final class VercelManager: @unchecked Sendable {
    static let shared = VercelManager()
    private init() {}

    func deploy(
        project: Project,
        token: String?,
        domain: String?,
        logHandler: @escaping (String) -> Void
    ) async throws -> DeploymentResult {
        do {
            logHandler("Starting Vercel deployment workflow for project: \(project.name)")
            logHandler("Vercel is configured to deploy via GitHub integration.")

            logHandler("Ensuring GitHub repository is up to date...")

            let repoPrepared = try await prepareGitHubRepository(project: project, logHandler: logHandler)

            guard repoPrepared else {
                return DeploymentResult(success: false, url: nil, errorMessage: "Failed to prepare GitHub repository for deployment.")
            }

            logHandler("✓ Changes successfully pushed to GitHub.")
            logHandler("Vercel will now automatically pick up the new commit and start a deployment.")

            let siteURL = domain != nil ? "https://\(domain!)" : "https://vercel.com/dashboard"
            return DeploymentResult(success: true, url: siteURL, errorMessage: nil)
        } catch {
            logHandler("DEPLOYMENT FAILED: \(error.localizedDescription)")
            return DeploymentResult(success: false, url: nil, errorMessage: error.localizedDescription)
        }
    }

    private func prepareGitHubRepository(project: Project, logHandler: @escaping (String) -> Void) async throws -> Bool {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            logHandler("CRITICAL ERROR: No GitHub repository is linked to this project.")
            throw NSError(domain: "VercelManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Deployment requires a connected GitHub repository."])
        }

        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)

        logHandler("Syncing codebase to GitHub repository: \(owner)/\(repo)")
        let projectDir = await project.directoryURL
        let files = collectProjectFiles(from: project.files, projectDir: projectDir)
        try await GitHubService.shared.pushProject(
            owner: owner,
            repo: repo,
            branch: "main",
            commitMessage: "Vercel Deployment Sync: \(Date().formatted())",
            files: files
        )

        return true
    }

    private func collectProjectFiles(from nodes: [FileNode], projectDir: URL) -> [(path: String, data: Data)] {
        var collected: [(path: String, data: Data)] = []
        for node in nodes {
            if node.isDirectory {
                collected += collectProjectFiles(from: node.children, projectDir: projectDir)
                continue
            }
            let fileURL = projectDir.appendingPathComponent(node.path)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            collected.append((path: node.path, data: Data(content.utf8)))
        }
        return collected
    }
}
