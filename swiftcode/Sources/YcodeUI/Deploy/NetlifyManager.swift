import Foundation
import SwiftCodeGitHub
import YcodeIDECore

final class NetlifyManager: @unchecked Sendable {
    static let shared = NetlifyManager()
    private init() {}

    func deploy(
        project: Project,
        token: String?,
        domain: String?,
        logHandler: @escaping (String) -> Void
    ) async throws -> DeploymentResult {
        do {
            logHandler("Starting Netlify deployment workflow for project: \(project.name)")
            logHandler("This service will commit the latest changes to GitHub.")
            logHandler("Netlify will automatically trigger a build from the linked repository.")

            logHandler("Preparing repository and pushing changes...")

            let repoPrepared = try await prepareGitHubRepository(project: project, logHandler: logHandler)

            guard repoPrepared else {
                return DeploymentResult(success: false, url: nil, errorMessage: "Failed to prepare GitHub repository for deployment.")
            }

            logHandler("✓ Changes successfully pushed to GitHub.")
            logHandler("Please check your Netlify dashboard for the build status.")

            let siteURL = domain != nil ? "https://\(domain!)" : "https://app.netlify.com"
            return DeploymentResult(success: true, url: siteURL, errorMessage: nil)
        } catch {
            logHandler("DEPLOYMENT FAILED: \(error.localizedDescription)")
            return DeploymentResult(success: false, url: nil, errorMessage: error.localizedDescription)
        }
    }

    private func prepareGitHubRepository(project: Project, logHandler: @escaping (String) -> Void) async throws -> Bool {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            logHandler("CRITICAL ERROR: No GitHub repository is linked to this project.")
            throw NSError(domain: "NetlifyManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Deployment requires a connected GitHub repository."])
        }

        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)

        logHandler("Pushing project files to \(owner)/\(repo) [main]")
        let projectDir = await project.directoryURL
        let files = collectProjectFiles(from: project.files, projectDir: projectDir)
        try await GitHubService.shared.pushProject(
            owner: owner,
            repo: repo,
            branch: "main",
            commitMessage: "Netlify Deployment: \(Date().formatted())",
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
