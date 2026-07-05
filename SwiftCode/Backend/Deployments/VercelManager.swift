import Foundation

final class VercelManager {
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

            // Independent repository preparation
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
        try await GitHubService.shared.pushProject(
            project,
            owner: owner,
            repo: repo,
            commitMessage: "Vercel Deployment Sync: \(Date().formatted())",
            branch: "main"
        )

        return true
    }
}
