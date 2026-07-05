import Foundation

final class NetlifyManager {
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

            // Re-implementing the core logic here for independence
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
        try await GitHubService.shared.pushProject(
            project,
            owner: owner,
            repo: repo,
            commitMessage: "Netlify Deployment: \(Date().formatted())",
            branch: "main"
        )

        return true
    }
}
